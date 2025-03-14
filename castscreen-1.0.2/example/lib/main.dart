import 'package:castscreen/castscreen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CastScreen Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'CastScreen Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var devices = <Device>[];
  Device? curDev;
  final playUrl =
      'https://leshiyuncdn.ahjunqin.top/20240109/BWCSLaI6/index.m3u8';

  Future<void> search() async {
    devices =
        await CastScreen.discoverDevice(timeout: const Duration(seconds: 3));
    curDev = null;
    setState(() {});
  }

  Future<void> play() async {
    if (curDev == null) {
      return;
    }
    final alive = await curDev!.alive();
    if (!alive) {
      return;
    }
    curDev!.setAVTransportURI(SetAVTransportURIInput(playUrl));
  }

  Future<void> stop() async {
    if (curDev == null) {
      return;
    }
    final alive = await curDev!.alive();
    if (!alive) {
      return;
    }
    curDev!.stop(const StopInput());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择设备:'),
              devices.isNotEmpty
                  ? DropdownButton<Device>(
                      value: curDev,
                      elevation: 16,
                      style: const TextStyle(color: Colors.deepPurple),
                      underline: Container(
                        height: 2,
                        color: Colors.deepPurpleAccent,
                      ),
                      onChanged: (Device? value) {
                        curDev = value;
                        setState(() {});
                      },
                      items: devices.map<DropdownMenuItem<Device>>((dev) {
                        return DropdownMenuItem<Device>(
                          value: dev,
                          child: Text(dev.spec.friendlyName),
                        );
                      }).toList(),
                    )
                  : const Text('无设备'),
              TextButton(onPressed: search, child: const Text('Search')),
              TextButton(onPressed: play, child: const Text('Play')),
              TextButton(onPressed: stop, child: const Text('Stop')),
            ],
          ),
        ));
  }
}
