import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/address_book.dart';
import '../../common/widgets/login.dart';
import '../../common/widgets/my_group.dart';
import '../../common/widgets/peer_card.dart';
import '../../common/widgets/peers_view.dart';
import '../../models/ab_model.dart';
import '../../models/peer_tab_model.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'preferences.dart';
import 'orientation.dart';

class IosDeviceHome extends StatefulWidget {
  final Widget connectionEntry;
  const IosDeviceHome({super.key, required this.connectionEntry});
  @override
  State<IosDeviceHome> createState() => _IosDeviceHomeState();
}

class _IosDeviceHomeState extends State<IosDeviceHome> {
  int _selected = 0;
  late final PeerUiType _previousStyle;
  List<String> get _labels => [
        if (!bind.isDisableAb() && !bind.isDisableAccount()) 'Address book',
        'Favorites',
        'Recent sessions',
        if (!bind.isDisableAb() && !bind.isDisableAccount()) 'Online',
        if (gFFI.peerTabModel.isEnabled[PeerTabIndex.group.index])
          'Accessible devices',
        if (gFFI.peerTabModel.isEnabled[PeerTabIndex.lan.index]) 'Discovered',
      ];
  @override
  void initState() {
    super.initState();
    _previousStyle = peerCardUiType.value;
    peerCardUiType.value = PeerUiType.list;
    _selected = int.tryParse(IosPreferences.read('device-section')) ?? 0;
    if (_selected < 0 || _selected >= _labels.length) _selected = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _select(_selected);
    });
  }

  @override
  void dispose() {
    peerCardUiType.value = _previousStyle;
    super.dispose();
  }

  void _select(int index) {
    final label = _labels[index];
    final tab = label == 'Favorites'
        ? PeerTabIndex.fav
        : label == 'Recent sessions'
            ? PeerTabIndex.recent
            : label == 'Accessible devices'
                ? PeerTabIndex.group
                : label == 'Discovered'
                    ? PeerTabIndex.lan
                    : PeerTabIndex.ab;
    gFFI.peerTabModel.setCurrentTab(tab.index);
    setState(() => _selected = index);
    IosPreferences.write('device-section', '$index');
    if (tab == PeerTabIndex.ab && gFFI.userModel.isLogin) {
      gFFI.abModel.pullAb(force: null, quiet: false);
    }
    if (tab == PeerTabIndex.group) gFFI.groupModel.pull(force: false);
  }

  Widget _devices() {
    switch (_labels[_selected]) {
      case 'Favorites':
        return FavoritePeersView();
      case 'Recent sessions':
        return RecentPeersView();
      case 'Accessible devices':
        return const MyGroup();
      case 'Discovered':
        return DiscoveredPeersView();
      case 'Online':
        return Obx(() => gFFI.userModel.isLogin
            ? _OnlinePeers()
            : Center(
                child: TextButton(
                    onPressed: loginDialog, child: Text(translate('Login')))));
      default:
        // A temporary API outage should not hide an already loaded address book.
        return Obx(() => gFFI.userModel.networkError.isNotEmpty &&
                gFFI.abModel.currentAbPeers.isNotEmpty
            ? Column(children: [
                ListTile(
                    leading: const Icon(Icons.cloud_off),
                    title: Text(gFFI.userModel.networkError.value)),
                Expanded(child: AddressBookPeersView()),
              ])
            : const AddressBook());
    }
  }

  void _refresh() {
    gFFI.userModel.refreshCurrentUser();
    if (gFFI.userModel.isLogin) {
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final labels = _labels;
        final devices = Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: peerSearchTextController,
                    onChanged: (value) => peerSearchText.value = value,
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: translate('Search'),
                        border: InputBorder.none))),
            IconButton(
                tooltip: translate('Refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: _refresh),
          ]),
          Expanded(child: _devices()),
        ]);
        final wide = size.maxWidth >= 700;
        return Column(children: [
          widget.connectionEntry,
          if (!wide)
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    children: List.generate(
                        labels.length,
                        (i) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                  label: Text(translate(labels[i])),
                                  selected: _selected == i,
                                  onSelected: (_) => _select(i)),
                            )))),
          Expanded(
              child: wide
                  ? Row(children: [
                      SizedBox(
                          width: 200,
                          child: ListView(
                              children: List.generate(
                                  labels.length,
                                  (i) => ListTile(
                                      title: Text(translate(labels[i])),
                                      selected: _selected == i,
                                      onTap: () => _select(i))))),
                      const VerticalDivider(width: 20),
                      Expanded(child: devices),
                    ])
                  : devices),
        ]);
      });
}

class _OnlinePeers extends StatefulWidget {
  @override
  State<_OnlinePeers> createState() => _OnlinePeersState();
}

class _OnlinePeersState extends State<_OnlinePeers> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _query();
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _query());
  }

  void _query() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        iosOrientation.inSession) {
      return;
    }
    final ids =
        gFFI.abModel.currentAbPeers.map((peer) => peer.id).take(1000).toList();
    if (ids.isNotEmpty) bind.queryOnlines(ids: ids);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: gFFI.abModel.peersModel,
      builder: (context, _) => Obx(() {
            final search = peerSearchText.value.toLowerCase();
            final peers = gFFI.abModel.currentAbPeers
                .where((peer) =>
                    peer.online &&
                    '${peer.alias} ${peer.id} ${peer.hostname}'
                        .toLowerCase()
                        .contains(search))
                .toList();
            if (peers.isEmpty) return Center(child: Text(translate('Empty')));
            return ListView.builder(
                itemCount: peers.length,
                itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SizedBox(
                        height: stateGlobal.isPortrait.isTrue ? null : 45,
                        child: AddressBookPeerCard(peer: peers[i]))));
          }));
}
