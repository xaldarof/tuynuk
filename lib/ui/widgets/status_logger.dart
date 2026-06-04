import 'package:flutter/material.dart';
import 'package:safe_file_sender/models/state_controller.dart';

class StatusLogger extends StatelessWidget {
  final List<TransferStateEnum> history;

  const StatusLogger({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white12,
      ),
      height: 300,
      width: MediaQuery.sizeOf(context).width,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...history.map(
              (e) => Container(
                margin: const EdgeInsets.only(top: 4, left: 4),
                alignment: Alignment.centerLeft,
                child: Text(
                  e.value,
                  style: const TextStyle(
                      color: Colors.white60, fontFamily: 'Hack', fontSize: 8),
                  textAlign: TextAlign.start,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
