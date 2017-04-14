// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apps.modular.services.device/device_shell.fidl.dart';
import 'package:apps.modular.services.device/user_provider.fidl.dart';
import 'package:lib.widgets/modular.dart';

export 'package:lib.widgets/model.dart' show ScopedModel, ScopedModelDescendant;

class UserPickerDeviceShellModel extends DeviceShellModel {
  List<String> _users;

  List<String> get users => _users;

  @override
  void onReady(
    UserProvider userProvider,
    DeviceShellContext deviceShellContext,
  ) {
    super.onReady(userProvider, deviceShellContext);
    _loadUsers();
  }

  void onLogout() {
    _users = null;
    notifyListeners();
    _loadUsers();
  }

  void _loadUsers() {
    userProvider.previousUsers((List<String> users) {
      _users = new List<String>.unmodifiable(users);
      notifyListeners();
    });
  }
}