import 'dart:async';
import 'dart:io';

import 'package:encrypt_shared_preferences/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:safe_file_sender/cache/hive/hive_manager.dart';
import 'package:safe_file_sender/cache/preferences_cache_keys.dart';
import 'package:safe_file_sender/common/app_temp_data.dart';
import 'package:safe_file_sender/common/constants.dart';
import 'package:safe_file_sender/models/path_values.dart';
import 'package:safe_file_sender/dev/logger.dart';
import 'package:safe_file_sender/l10n/gen/app_localizations.dart';
import 'package:safe_file_sender/models/environment.dart';
import 'package:safe_file_sender/ui/history/transmission_history_screen.dart';
import 'package:safe_file_sender/ui/main/bloc/main_bloc.dart';
import 'package:safe_file_sender/ui/navigation/custom_page_transition.dart';
import 'package:safe_file_sender/ui/pin/pin_screen.dart';
import 'package:safe_file_sender/ui/receive_screen.dart';
import 'package:safe_file_sender/ui/send_screen.dart';
import 'package:safe_file_sender/ui/theme.dart';
import 'package:safe_file_sender/ui/widgets/common_inherited_widget.dart';
import 'package:safe_file_sender/ui/widgets/scale_tap.dart';
import 'package:safe_file_sender/utils/context_utils.dart';
import 'package:safe_file_sender/utils/file_utils.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await HiveManager.init();

  await EncryptedSharedPreferences.initialize(Environment.key);
  runApp(
    Tuynuk(),
  );
}

class Tuynuk extends StatelessWidget {
  Tuynuk({super.key});

  final MainBloc _bloc = MainBloc();
  final _appTempData = AppTempData();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MainBloc>(
      create: (_) => _bloc,
      child: BlocConsumer<MainBloc, MainState>(
        builder: (context, state) {
          return CommonInheritedWidget(
            EncryptedSharedPreferences.getInstance(),
            _appTempData,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routes: {
                PathValues.send: (context) => SendScreen(
                    sharedFile: ModalRoute.of(context)?.settings.arguments
                        as SharedMediaFile?),
                PathValues.receive: (context) => const ReceiveScreen(),
                PathValues.pin: (context) => const PinScreen(),
                PathValues.history: (context) =>
                    const TransmissionHistoryScreen(),
                PathValues.home: (context) => const HomeScreen(),
              },
              locale: Locale(EncryptedSharedPreferences.getInstance().getString(
                  PreferencesCacheKeys.localeCode,
                  defaultValue:
                      AppLocalizations.supportedLocales.first.languageCode)!),
              debugShowCheckedModeBanner: false,
              onGenerateTitle: (context) => context.localization.appName,
              theme: ThemeData(
                primaryColor: Colors.white,
                textTheme: AppTheme.textTheme,
                hintColor: Colors.white12,
                scaffoldBackgroundColor: Colors.black,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
                useMaterial3: false,
                pageTransitionsTheme: PageTransitionsTheme(builders: {
                  TargetPlatform.android: CustomPageTransitionBuilder(),
                  TargetPlatform.iOS: CustomPageTransitionBuilder(),
                }),
              ),
              home: const PinScreen(),
            ),
          );
        },
        listener: (context, state) {
          //
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late StreamSubscription _sharingIntentSubscription;

  @override
  void initState() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((value) {
      _handleSharingIntent();
      _initQuickActions();
    });
  }

  _handleAction(String actionType) {
    if (actionType == PathValues.send) {
      if (!Navigator.canPop(context)) {
        Navigator.pushNamed(context, PathValues.send);
      }
    }
    if (actionType == PathValues.receive) {
      if (!Navigator.canPop(context)) {
        Navigator.pushNamed(context, PathValues.receive);
      }
    }
  }

  _initQuickActions() {
    const QuickActions quickActions = QuickActions();
    quickActions.initialize((String shortcutType) {
      _handleAction(shortcutType);
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      ShortcutItem(
          type: PathValues.receive,
          localizedTitle: context.localization.receive,
          icon: 'baseline_arrow_downward_24'),
      ShortcutItem(
          type: PathValues.send,
          localizedTitle: context.localization.send,
          icon: 'baseline_arrow_upward_24'),
    ]);
  }

  @override
  void dispose() {
    FileUtils.clearDecryptedCache();
    _sharingIntentSubscription.cancel();
    super.dispose();
  }

  Future<void> _handleSharingIntent() async {
    try {
      if (!(Platform.isAndroid || Platform.isIOS)) return;
      _sharingIntentSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen((value) {
        if (!Navigator.canPop(context) && value.isNotEmpty) {
          Navigator.pushNamed(context, PathValues.send, arguments: value.first);
          ReceiveSharingIntent.instance.reset();
        }
        logMessage(value.map((f) => f.toMap()));
      }, onError: (err) {
        logMessage(err);
      });
      ReceiveSharingIntent.instance.getInitialMedia().then((value) {
        if (value.isNotEmpty) {
          Navigator.pushNamed(context, PathValues.send, arguments: value.first);
          ReceiveSharingIntent.instance.reset();
        }
      });
    } catch (e) {
      // Handle exceptions
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: DropdownButton<Locale>(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                underline: const SizedBox.shrink(),
                icon: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Colors.deepPurple[300],
                hint: Text(context.localization.language,
                    style: AppTheme.textTheme.titleMedium),
                onChanged: (Locale? locale) {
                  if (locale == null) return;
                  context.read<MainBloc>().add(UpdateLocalization(locale));
                  _initQuickActions();
                },
                items: AppLocalizations.supportedLocales.map((e) {
                  return DropdownMenuItem(
                    value: Locale(e.languageCode, ''),
                    child: Text(
                      e.languageCode,
                      style: AppTheme.textTheme.titleMedium,
                    ),
                  );
                }).toList(),
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: IconButton(
                  onPressed: () {
                    Navigator.pushNamed(context, PathValues.history);
                  },
                  icon: const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, PathValues.send);
                    },
                    child: Text(
                      context.localization.send,
                      style: AppTheme.textTheme.titleMedium,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, PathValues.receive);
                    },
                    child: Text(
                      context.localization.receive,
                      style: AppTheme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ScaleTap(
                onPressed: () {
                  launchUrl(Uri.parse(Constants.sourceUrl),
                      mode: LaunchMode.externalApplication);
                },
                child: Container(
                  margin: const EdgeInsets.all(12),
                  child: Text(
                    context.localization.sourceCode,
                    style: AppTheme.textTheme.titleMedium
                        ?.copyWith(color: Colors.white60, fontSize: 8),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
