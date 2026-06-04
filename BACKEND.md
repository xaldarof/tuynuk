# Tuynuk — Ядро бэкенда

Документ описывает ключевые механизмы сервера: генерацию сессий, обмен ключами, передачу файлов и очистку состояния.
Основной код — `Tuynuk.Api/` и `Tuynuk.Infrastructure/` в `/Users/temurxoldarov/dev/tuynuk-api`.

---

## 1. Генерация уникального идентификатора сессии

Идентификатор — случайная строка из букв `A-Z` и цифр `0-9` длиной **6 символов** (задаётся в `appsettings.json`).
Генерация повторяется до тех пор, пока не окажется уникальной в базе.

```csharp
// Tuynuk.Api/Services/Sessions/SessionService.cs:130
private string GenerateRandomIdentifier(int length = 6)
{
    var identifierBuilder = new StringBuilder(length);
    for (int i = 0; i < length; i++)
    {
        int randomIndex = _random.Next(0, ALLOWED_IDENTIFIER_CHARS.Length);
        identifierBuilder.Append(ALLOWED_IDENTIFIER_CHARS[randomIndex]);
    }
    return identifierBuilder.ToString();
}

private async Task<string> GenerateUniqueIdentifierAsync(int length)
{
    string identifier = GenerateRandomIdentifier(length);
    while (await DoesIdentifierExistAsync(identifier))
        identifier = GenerateRandomIdentifier(length);
    return identifier;
}
```

`ALLOWED_IDENTIFIER_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` — 36 символов, 36⁶ ≈ 2.2 млрд комбинаций.

---

## 2. Хэширование идентификатора (SHA-256)

В базе данных идентификатор хранится **только в виде SHA-256 хэша** — прямой доступ к БД не позволяет угадать или перебрать коды активных сессий.

```csharp
// Tuynuk.Api/Extensions/StringExtensions.cs:8
public static string ToSHA256Hash(this string value)
{
    using (SHA256 sha256 = SHA256.Create())
    {
        byte[] bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(value));
        var builder = new StringBuilder();
        foreach (byte b in bytes)
            builder.Append(b.ToString("x2"));
        return builder.ToString();
    }
}
```

Хэширование применяется в двух местах:
- при создании сессии: `identifier.ToSHA256Hash()` → запись в БД
- при поиске сессии: `view.Identifier.ToSHA256Hash()` → запрос к БД

Клиент всегда работает с открытым кодом, сервер — только с его хэшем.

---

## 3. Создание сессии и регистрация получателя

При вызове `CreateSession` через SignalR сервер создаёт сессию, регистрирует клиента как `Receiver` с его публичным ключом и возвращает открытый код сессии.

```csharp
// Tuynuk.Api/Services/Sessions/SessionService.cs:51
public async Task<Guid> CreateSessionAsync(CreateSessionViewModel view)
{
    int identifierLength = Configuration.GetValue<int>("UniqueIdentifierLength");
    var identifier = await GenerateUniqueIdentifierAsync(identifierLength);

    string hashedIdentifier = identifier.ToSHA256Hash();

    var session = new Session() { Identifier = hashedIdentifier };
    await _sessionRepository.AddAsync(session);

    var receiverClient = new Client(view.ConnectionId, ClientType.Receiver, session.Id, view.PublicKey);
    await _clientRepository.AddAsync(receiverClient);

    await _sessionHub.Clients.Client(receiverClient.ConnectionId).OnSessionCreated(identifier);

    return session.Id;
}
```

`OnSessionCreated(identifier)` — отправляет **открытый** код сессии только создателю. Он передаёт его отправителю по внешнему каналу (QR-код, вручную).

---

## 4. Присоединение отправителя и обмен публичными ключами

При `JoinSession` сервер находит сессию, регистрирует `Sender` и **одновременно** отправляет каждому участнику публичный ключ другой стороны.

```csharp
// Tuynuk.Api/Services/Sessions/SessionService.cs:78
public async Task<Guid> JoinSessionAsync(JoinSessionViewModel view)
{
    view.Identifier = view.Identifier.ToSHA256Hash();

    var session = await _sessionRepository.GetAll()
                    .Include(l => l.Clients)
                    .FirstOrDefaultAsync(l => l.Identifier == view.Identifier);

    // проверка: сессия существует, Sender ещё не подключён
    var senderClient = new Client(view.ConnectionId, ClientType.Sender, session.Id, view.PublicKey);
    await _clientRepository.AddAsync(senderClient);

    var receiverClient = session.Clients.FirstOrDefault(l => l.Type == ClientType.Receiver);

    await _sessionHub.Clients.Client(receiverClient.ConnectionId).OnSessionReady(senderClient.PublicKey);
    await _sessionHub.Clients.Client(senderClient.ConnectionId).OnSessionReady(receiverClient.PublicKey);

    return session.Id;
}
```

После `OnSessionReady` оба клиента независимо вычисляют один и тот же ECDH-секрет. Сервер публичные ключи только ретранслирует — общий секрет никогда не покидает клиентов.

---

## 5. Загрузка файла и уведомление получателя

`UploadFile` принимает зашифрованный файл, сохраняет его в БД вместе с HMAC и уведомляет получателя через SignalR.

```csharp
// Tuynuk.Api/Services/Files/FileService.cs:92
public async Task<Guid> UploadFileAsync(IFormFile formfile, string sessionIdentifier, string HMAC)
{
    string hashedIdentifier = sessionIdentifier.ToSHA256Hash();
    var session = await _sessionRepository.GetAll()
                        .Include(l => l.Clients)
                        .FirstOrDefaultAsync(l => l.Identifier == hashedIdentifier);

    byte[] fileContent;
    using (var ms = new MemoryStream())
    {
        formfile.CopyTo(ms);
        fileContent = ms.ToArray();
    }

    var file = new File(fileContent, formfile.FileName, session.Id, HMAC);
    await _filesRepository.AddAsync(file);

    var receiverClient = session.Clients.FirstOrDefault(l => l.Type == ClientType.Receiver);
    await _sessionHub.Clients.Client(receiverClient.ConnectionId).OnFileUploaded(file.Id, file.Name, HMAC);

    return file.Id;
}
```

`OnFileUploaded(fileId, fileName, HMAC)` — получатель узнаёт ID файла и HMAC, не скачивая содержимое.

---

## 6. Одноразовое скачивание файла

Файл можно скачать **строго один раз**. При повторном запросе — ошибка. После успешной отдачи файла сессия полностью удаляется из БД.

```csharp
// Tuynuk.Api/Services/Files/FileService.cs:50
public async Task<GetFileViewModel> GetFileAsync(Guid fileId)
{
    var file = await _filesRepository.GetAll()
                        .Include(l => l.Session)
                        .FirstOrDefaultAsync(l => l.Id == fileId);

    if (file.Session.IsFileDownloadRequested)
        throw new FileAlreadyRequestedEx("File is already requested for downloading");

    file.Session.IsFileDownloadRequested = true;
    _sessionRepository.Update(file.Session);
    await _sessionRepository.DbContext.SaveChangesAsync();

    // HMAC возвращается в заголовке ответа, не в теле
    HttpContext.Response.Headers.Append("HMAC", file.HMAC);

    // сессия удаляется сразу после отдачи файла
    _sessionRepository.Remove(file.Session);
    await _filesRepository.SaveChangesAsync();

    return new GetFileViewModel { Name = file.Name, Content = new MemoryStream(file.Content) };
}
```

HMAC передаётся в HTTP-заголовке `HMAC` — клиент сверяет его с локально вычисленным до расшифровки файла.

---

## 7. Отключение клиента

При разрыве SignalR-соединения `ConnectionId` клиента обнуляется. Сессия при этом не удаляется — она очищается отдельно (см. п. 8).

```csharp
// Tuynuk.Api/Hubs/Sessions/SessionHub.cs:74
public override async Task OnDisconnectedAsync(Exception ex)
{
    var disconnectedClient = await _clientRepository.GetAll()
        .FirstOrDefaultAsync(l => l.ConnectionId == Context.ConnectionId);

    if (disconnectedClient != null)
    {
        disconnectedClient.ConnectionId = null;
        _clientRepository.Update(disconnectedClient);
        await _clientRepository.SaveChangesAsync();
    }

    await base.OnDisconnectedAsync(ex);
}
```

`ConnectionId == null` — признак того, что клиент сейчас офлайн. Используется при поиске `Receiver` перед отправкой уведомления.

---

## 8. Автоочистка брошенных сессий (Hangfire)

Раз в час Hangfire запускает задачу, которая удаляет сессии, чей `Receiver` ушёл офлайн (больше нет смысла ждать отправителя).

```csharp
// Tuynuk.Api/Services/Sessions/SessionService.cs:152
public async Task RemoveAbandonedSessionsAsync()
{
    using (var scope = _serviceProvider.CreateScope())
    {
        var sessionRepository = scope.ServiceProvider.GetRequiredService<ISessionRepository>();
        var abandonedSessions = await sessionRepository.GetAll()
                                .Where(l => l.Clients.Any(
                                    l => l.ConnectionId == null && l.Type == ClientType.Receiver))
                                .ToListAsync();

        if (abandonedSessions.Any())
        {
            sessionRepository.RemoveRange(abandonedSessions);
            await sessionRepository.SaveChangesAsync();
        }
    }
}
```

Регистрация в `Program.cs`:
```csharp
// Tuynuk.Api/Program.cs:63
RecurringJob.AddOrUpdate<ISessionService>(
    "RemoveAbandonedSessions",
    l => l.RemoveAbandonedSessionsAsync(),
    Cron.Hourly());
```

---

## Жизненный цикл сессии

```
Receiver                     Сервер                      Sender
────────                     ──────                      ──────
CreateSession(pubKey) ──▶   session + Receiver в БД
                            OnSessionCreated(id) ──▶     (передаёт id по внешнему каналу)
                                                 ◀──     JoinSession(id, pubKey)
                            Sender добавлен в БД
OnSessionReady(senderPub) ◀─────────────────────────▶   OnSessionReady(receiverPub)
[ECDH → sharedKey]                                       [ECDH → sharedKey]
                                             ◀──────     POST /api/Files/UploadFile
                            файл + HMAC сохранены в БД
OnFileUploaded(id, name, hmac) ◀──
GET /api/Files/GetFile ──▶  HMAC в заголовке, файл в теле
                            сессия удалена из БД
[HMAC проверен, файл расшифрован]
```
