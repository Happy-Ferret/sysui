// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lib.logging/logging.dart';

/// Displays a memory indicator.
class MemoryIndicator extends StatefulWidget {
  @override
  _MemoryIndicatorState createState() => new _MemoryIndicatorState();
}

class _MemoryIndicatorState extends State<MemoryIndicator> {
  String _freeMemory;

  @override
  void initState() {
    super.initState();
    _checkMemory();
  }

  void _checkMemory() {
    // Determines the amount of free memory available.
    Process.run('/boot/bin/kstats', <String>['-m', '-n 1']).then(
        (ProcessResult results) {
      List<String> lines = results.stdout.split('\n');
      if (lines.length < 2) {
        log.fine('ERROR parsing kstats output:\n${results.stdout}');
      } else {
        List<String> memories = lines[1].trim().split(new RegExp(r'(\s+)'));
        if (memories.length < 2) {
          log.fine('ERROR parsing kstats output:\n${results.stdout}');
        } else {
          setState(() {
            _freeMemory = memories[1];
          });
        }
      }
      new Timer(const Duration(seconds: 5), _checkMemory);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _freeMemory == null
        ? new Offstage()
        : new Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            new Icon(Icons.memory, color: Colors.white, size: 12.0),
            new Container(height: 0.0, width: 4.0),
            new Text('$_freeMemory', style: const TextStyle(fontSize: 12.0))
          ]);
  }
}
