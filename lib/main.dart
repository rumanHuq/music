import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class Song {
  String title;
  String url;
  bool playingNow = false;

  Song({required this.title, required this.url});
}

class PlaylistsNotifier extends StateNotifier<AsyncValue<List<Song>>> {
  final Reader read;
  PlaylistsNotifier({required this.read, AsyncValue<List<Song>>? playlist})
      : super(playlist ?? const AsyncValue.loading()) {
    _getPlaylist();
  }

  Future<void> _getPlaylist() async {
    final String response = await rootBundle.loadString('assets/playlist.json');
    final List<dynamic> playlist = await jsonDecode(response);
    final playlists = playlist.map((p) {
      return Song(title: p["title"], url: p["url"]);
    }).toList();
    state = AsyncValue.data(playlists);
  }

  Future<void> setActiveSong(int activeSongIndex) async {
    state = state.whenData((value) {
      return value.asMap().entries.map((keyVal) {
        keyVal.value.playingNow = false;
        if (keyVal.key == activeSongIndex) {
          keyVal.value.playingNow = true;
        }
        return keyVal.value;
      }).toList();
    });
  }
}

final playListProvider = StateNotifierProvider.autoDispose<PlaylistsNotifier, AsyncValue<List<Song>>>((ref) {
  return PlaylistsNotifier(read: ref.read);
});

class PlayController extends StatelessWidget {
  const PlayController({
    Key? key,
    required this.playingNowItem,
    required this.onSetplayingNow,
    required this.audioPlayerIsPlaying,
    required this.player,
  }) : super(key: key);

  final Song? playingNowItem;
  final void Function({required String going, required String songTitle}) onSetplayingNow;
  final ValueNotifier<bool?> audioPlayerIsPlaying;
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 40.0,
          onPressed: playingNowItem != null
              ? () {
                  onSetplayingNow(songTitle: playingNowItem!.title, going: "previous");
                }
              : null,
        ),
        IconButton(
          icon: Icon(audioPlayerIsPlaying.value == false ? Icons.pause : Icons.play_arrow),
          iconSize: 60.0,
          onPressed: () async {
            if (playingNowItem == null) {
              onSetplayingNow(songTitle: "", going: "current");
            }
            if (audioPlayerIsPlaying.value == true) {
              await player.resume();
            } else {
              await player.pause();
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 40.0,
          onPressed:
              playingNowItem != null ? () => onSetplayingNow(songTitle: playingNowItem!.title, going: "next") : null,
        ),
      ],
    );
  }
}

class Seeker extends HookWidget {
  const Seeker({Key? key}) : super(key: key);

  String toFormattedTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');

    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return [if (duration.inHours > 0) hours, minutes, seconds].join(":");
  }

  @override
  Widget build(BuildContext context) {
    final duration = useState(Duration.zero);
    final position = useState(Duration.zero);
    final player = GetIt.I<AudioPlayer>();

    useEffect(() {
      player.onDurationChanged.listen((newDuration) {
        duration.value = newDuration;
      });

      player.onAudioPositionChanged.listen((newPosition) {
        position.value = newPosition;
      });
      return () {
        player.dispose();
      };
    }, []);

    return Column(
      children: [
        Slider(
          min: 0,
          max: position.value.inSeconds.toDouble(),
          value: position.value.inSeconds.toDouble(),
          onChanged: (_) async {},
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(toFormattedTime(duration.value)),
            Text(toFormattedTime(duration.value - position.value)),
          ],
        )
      ],
    );
  }
}

class MusicPlayer extends HookWidget {
  final Song? playingNowItem;
  final void Function({required String songTitle, required String going}) onSetplayingNow;

  const MusicPlayer({
    Key? key,
    required this.playingNowItem,
    required this.onSetplayingNow,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final player = GetIt.I<AudioPlayer>();
    final audioPlayerIsPlaying = useState<bool?>(null);

    useEffect(() {
      player.onPlayerStateChanged.listen((event) {
        if (event == PlayerState.PLAYING) {
          audioPlayerIsPlaying.value = false;
        }
        if (event == PlayerState.PAUSED) {
          audioPlayerIsPlaying.value = true;
        }
      });
      return () => player.dispose();
    }, []);

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(10),
      ),
      width: MediaQuery.of(context).size.width * 0.9,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Seeker(),
            PlayController(
                playingNowItem: playingNowItem,
                onSetplayingNow: onSetplayingNow,
                audioPlayerIsPlaying: audioPlayerIsPlaying,
                player: player),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends HookConsumerWidget {
  final String title;
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistState = ref.watch(playListProvider);
    final playlistMethods = ref.read(playListProvider.notifier);
    final deviceSize = MediaQuery.of(context).size;
    final player = GetIt.I<AudioPlayer>();

    return Scaffold(
      body: playlistState.when(data: (data) {
        final playingNowItem = data.where((item) => item.playingNow == true);
        if (playingNowItem.isNotEmpty) {
          player.setUrl(playingNowItem.first.url).then((value) => player.resume());
        }
        return Column(
          children: [
            SizedBox(
              height: deviceSize.height * 0.7,
              child: ListView.builder(
                itemCount: data.length,
                itemBuilder: (ctx, idx) {
                  final song = data[idx];
                  return Card(
                    color: song.playingNow == true ? Colors.blue[400] : null,
                    child: ListTile(
                      onTap: () async {
                        await playlistMethods.setActiveSong(idx);
                      },
                      title: Text(
                        song.title,
                        style: TextStyle(color: song.playingNow == true ? Colors.white : null),
                      ),
                      trailing: song.playingNow == true
                          ? Icon(Icons.play_arrow_outlined, color: song.playingNow == true ? Colors.white : null)
                          : null,
                    ),
                  );
                },
              ),
            ),
            MusicPlayer(
              playingNowItem: playingNowItem.isNotEmpty ? playingNowItem.first : null,
              onSetplayingNow: ({required String songTitle, required String going}) async {
                final currentPlayingIndex = data.indexWhere((element) => element.title == songTitle);
                if (currentPlayingIndex != -1) {
                  if (going == "next" && data.length - 1 != currentPlayingIndex) {
                    await playlistMethods.setActiveSong(currentPlayingIndex + 1);
                  } else if (going == "previous" && currentPlayingIndex != 0) {
                    await playlistMethods.setActiveSong(currentPlayingIndex - 1);
                  }
                } else if (going == "current" && playingNowItem.isEmpty) {
                  await playlistMethods.setActiveSong(0);
                }
              },
            )
          ],
        );
      }, error: (e, st) {
        print(e);
        return const Text("Oh no");
      }, loading: () {
        return const CircularProgressIndicator();
      }),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyHomePage(title: 'Dynamic Widget Demo'),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final audioplayer = AudioPlayer();
  GetIt.I.registerSingleton(audioplayer);
  return runApp(const ProviderScope(child: MyApp()));
}
