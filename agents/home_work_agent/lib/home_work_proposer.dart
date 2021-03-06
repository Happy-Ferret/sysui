// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' as convert;
import 'dart:io';

import 'package:apps.maxwell.services.context/context_reader.fidl.dart';
import 'package:apps.maxwell.services.context/metadata.fidl.dart';
import 'package:apps.maxwell.services.context/value_type.fidl.dart';
import 'package:apps.maxwell.services.suggestion/ask_handler.fidl.dart';
import 'package:apps.maxwell.services.suggestion/proposal.fidl.dart';
import 'package:apps.maxwell.services.suggestion/proposal_publisher.fidl.dart';
import 'package:apps.maxwell.services.suggestion/suggestion_display.fidl.dart';
import 'package:apps.maxwell.services.suggestion/user_input.fidl.dart';

const String _kConfigFile =
    '/system/data/sysui/contextual_location_proposals.json';
const String _kDataConfigFile = '/data/contextual_location_proposals.json';
const String _kAskProposalsFile = '/system/data/sysui/ask_proposals.json';

const String _kLocationHomeWorkTopic = 'location/home_work';

const String _kLaunchEverythingProposalId = 'demo_all';

/// Proposes suggestions for home and work locations.
class HomeWorkProposer {
  final AskHandlerBinding _askHandlerBinding = new AskHandlerBinding();
  final _ContextAwareProposer _contextAwareProposer =
      new _ContextAwareProposer();

  /// Starts the proposal process.
  void start(
    ContextReader contextReader,
    ProposalPublisher proposalPublisher,
  ) {
    _contextAwareProposer.start(contextReader, proposalPublisher);

    final List<Map<String, String>> askProposals = convert.JSON.decode(
      new File(_kAskProposalsFile).readAsStringSync(),
    );

    proposalPublisher.registerAskHandler(
      _askHandlerBinding.wrap(new _AskHandlerImpl(askProposals: askProposals)),
    );
  }

  /// Cleans up any handles opened by [start].
  void stop() {
    _contextAwareProposer.stop();
    _askHandlerBinding.close();
  }
}

class _ContextAwareProposer {
  final ContextListenerBinding _contextListenerBinding =
      new ContextListenerBinding();

  void start(
    ContextReader contextReader,
    ProposalPublisher proposalPublisher,
  ) {
    final Map<String, List<Map<String, String>>> proposals =
        convert.JSON.decode(
      new File(_kConfigFile).readAsStringSync(),
    );

    File dataProposalFile = new File(_kDataConfigFile);

    final Map<String, List<Map<String, String>>> dataProposals =
        dataProposalFile.existsSync()
            ? convert.JSON.decode(
                dataProposalFile.readAsStringSync(),
              )
            : <String, List<Map<String, String>>>{};

    if (proposals.keys.contains('unknown')) {
      proposals['unknown'].forEach((Map<String, String> proposal) {
        proposalPublisher.propose(_createProposal(proposal));
      });
    }

    if (dataProposals.keys.contains('unknown')) {
      dataProposals['unknown'].forEach((Map<String, String> proposal) {
        proposalPublisher.propose(_createProposal(proposal));
      });
    }

    ContextSelector selector = new ContextSelector();
    selector.type = ContextValueType.entity;
    selector.meta = new ContextMetadata();
    selector.meta.entity = new EntityMetadata()..topic = _kLocationHomeWorkTopic;
    ContextQuery query = new ContextQuery();
    query.selector = <String, ContextSelector>{_kLocationHomeWorkTopic: selector};

    contextReader.subscribe(
      query,
      _contextListenerBinding.wrap(
        new _ContextListenerImpl(
          proposalPublisher: proposalPublisher,
          onTopicChanged: (String locationJson) {
            final Map<String, String> json = convert.JSON.decode(locationJson);
            if (json['location']?.isEmpty ?? true) {
              return;
            }

            // Remove all proposals.
            proposals.values.forEach(
              (List<Map<String, String>> proposalCategories) =>
                  proposalCategories.forEach(
                    (Map<String, String> proposal) =>
                        proposalPublisher.remove(proposal['id']),
                  ),
            );

            dataProposals.values.forEach(
              (List<Map<String, String>> proposalCategories) =>
                  proposalCategories.forEach(
                    (Map<String, String> proposal) =>
                        proposalPublisher.remove(proposal['id']),
                  ),
            );

            // Add proposals for this location.
            if (proposals.keys.contains(json['location'])) {
              proposals[json['location']]
                  .forEach((Map<String, String> proposal) {
                proposalPublisher.propose(_createProposal(proposal));
              });
            }

            if (dataProposals.keys.contains(json['location'])) {
              dataProposals[json['location']]
                  .forEach((Map<String, String> proposal) {
                proposalPublisher.propose(_createProposal(proposal));
              });
            }
          },
        ),
      ),
    );
  }

  void stop() {
    _contextListenerBinding.close();
  }
}

typedef void _OnTopicChanged(String topicValue);

class _ContextListenerImpl extends ContextListener {
  final ProposalPublisher proposalPublisher;
  final _OnTopicChanged onTopicChanged;

  _ContextListenerImpl({this.proposalPublisher, this.onTopicChanged});

  @override
  void onContextUpdate(ContextUpdate result) {
    if (result.values[_kLocationHomeWorkTopic].length > 0) {
      onTopicChanged(result.values[_kLocationHomeWorkTopic][0].content);
    }
  }
}

class _AskHandlerImpl extends AskHandler {
  final List<Map<String, String>> askProposals;

  _AskHandlerImpl({this.askProposals});

  @override
  void ask(UserInput query, void callback(List<Proposal> proposals)) {
    List<Proposal> proposals = <Proposal>[];

    if (query.text?.toLowerCase()?.startsWith('demo') ?? false) {
      proposals.addAll(askProposals.map(_createProposal));
      proposals.add(_launchEverythingProposal);
    }

    if ((query.text?.toLowerCase()?.startsWith('per') ?? false) ||
        (query.text?.toLowerCase()?.contains('3d') ?? false)) {
      proposals.add(
        _createAppProposal(
          id: 'Launch Perspective 3D demo',
          appUrl: 'perspective',
          headline: 'Launch Perspective 3D demo',
          imageType: SuggestionImageType.other,
          imageUrl: 'https://goo.gl/bi9jBa',
          color: 0xFF4A78C0,
        ),
      );
    }

    if ((query.text?.length ?? 0) >= 4) {
      void scanDirectory(Directory directory) {
        directory
            .listSync(recursive: true, followLinks: false)
            .map((FileSystemEntity fileSystemEntity) => fileSystemEntity.path)
            .where((String path) => path.contains(query.text))
            .where((String path) => FileSystemEntity.isFileSync(path))
            .forEach((String path) {
          String name = Uri.parse(path).pathSegments.last;
          String iconUrl =
              'https://www.gstatic.com/images/icons/material/system/2x/web_asset_grey600_48dp.png';
          int color = 0xFF000000 + (name.hashCode % 0xFFFFFF);
          if (name.contains('youtube')) {
            iconUrl = '/system/data/sysui/youtube_96dp.png';
            color = 0xFFEC2F01;
          } else if (name.contains('music')) {
            iconUrl = '/system/data/sysui/music_96dp.png';
            color = 0xFF3E2723;
          } else if (name.contains('email')) {
            iconUrl = '/system/data/sysui/inbox_96dp.png';
            color = 0xFF4285F4;
          } else if (name.contains('chat')) {
            iconUrl = '/system/data/sysui/chat_96dp.png';
            color = 0xFF9C26B0;
          } else if (path.contains('youtube')) {
            iconUrl = '/system/data/sysui/youtube_96dp.png';
            color = 0xFFEC2F01;
          } else if (path.contains('music')) {
            iconUrl = '/system/data/sysui/music_96dp.png';
            color = 0xFF3E2723;
          } else if (path.contains('email')) {
            iconUrl = '/system/data/sysui/inbox_96dp.png';
            color = 0xFF4285F4;
          } else if (path.contains('chat')) {
            iconUrl = '/system/data/sysui/chat_96dp.png';
            color = 0xFF9C26B0;
          }

          proposals.add(
            _createAppProposal(
              id: 'open $name',
              appUrl: 'file://$path',
              headline: 'Launch $name',
              // TODO(design): Find a better way to add indicators to the
              // suggestions about their provenance, lack of safety, etc. that
              // would be useful for developers but not distracting in demos
              // subheadline: '(This is potentially unsafe)',
              iconUrls: <String>[iconUrl],
              color: color,
            ),
          );
        });
      }

      scanDirectory(new Directory('/system/apps/'));
      scanDirectory(new Directory('/system/pkgs/'));
    }

    callback(proposals);
  }

  Proposal get _launchEverythingProposal => new Proposal()
    ..id = _kLaunchEverythingProposalId
    ..display = (new SuggestionDisplay()
      ..headline = 'Launch everything'
      ..subheadline = ''
      ..details = ''
      ..color = 0xFFFF0080
      ..iconUrls = const <String>[]
      ..imageType = SuggestionImageType.other
      ..imageUrl = ''
      ..annoyance = AnnoyanceType.none)
    ..onSelected = askProposals
        .map(
          (Map<String, String> proposal) => new Action()
            ..createStory = (new CreateStory()
              ..moduleId = proposal['module_url'] ?? ''
              ..initialData = proposal['module_data'] ?? ''),
        )
        .toList();
}

Proposal _createProposal(Map<String, String> proposal) => new Proposal()
  ..id = proposal['id']
  ..display = (new SuggestionDisplay()
    ..headline = proposal['headline'] ?? ''
    ..subheadline = proposal['subheadline'] ?? ''
    ..details = ''
    ..color = (proposal['color'] != null && proposal['color'].isNotEmpty)
        ? int.parse(proposal['color'], onError: (_) => 0xFFFF0080)
        : 0xFFFF0080
    ..iconUrls = proposal['icon_url'] != null
        ? <String>[proposal['icon_url']]
        : const <String>[]
    ..imageType = 'person' == proposal['type']
        ? SuggestionImageType.person
        : SuggestionImageType.other
    ..imageUrl = proposal['image_url'] ?? ''
    ..annoyance = AnnoyanceType.none)
  ..onSelected = <Action>[
    new Action()
      ..createStory = (new CreateStory()
        ..moduleId = proposal['module_url'] ?? ''
        ..initialData = proposal['module_data'] ?? '')
  ];

Proposal _createAppProposal({
  String id,
  String appUrl,
  String headline,
  String subheadline,
  String imageUrl: '',
  String initialData,
  SuggestionImageType imageType: SuggestionImageType.other,
  List<String> iconUrls = const <String>[],
  int color,
  AnnoyanceType annoyanceType: AnnoyanceType.none,
}) =>
    new Proposal()
      ..id = id
      ..display = (new SuggestionDisplay()
        ..headline = headline
        ..subheadline = subheadline ?? ''
        ..details = ''
        ..color = color
        ..iconUrls = iconUrls
        ..imageType = imageType
        ..imageUrl = imageUrl
        ..annoyance = annoyanceType)
      ..onSelected = <Action>[
        new Action()
          ..createStory = (new CreateStory()
            ..moduleId = appUrl
            ..initialData = initialData)
      ];
