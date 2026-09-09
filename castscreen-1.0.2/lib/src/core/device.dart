/*
<root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion>
        <major>1</major>
        <minor>0</minor>
    </specVersion>
    <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <presentationURL>/</presentationURL>
        <friendlyName>客厅的小米电视</friendlyName>
        <manufacturer>Xiaomi</manufacturer>
        <manufacturerURL>http://www.xiaomi.com/</manufacturerURL>
        <modelDescription>Xiaomi MediaRenderer</modelDescription>
        <modelName>Xiaomi MediaRenderer</modelName>
        <modelURL>http://www.xiaomi.com/hezi</modelURL>
        <UPC>000000000000</UPC>
        <UDN>uuid:4b363f50-e15b-37b8-0b7c-0154aba720bb</UDN>
        <serviceList>
            <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <controlURL>_urn:schemas-upnp-org:service:AVTransport_control</controlURL>
                <SCPDURL>_urn:schemas-upnp-org:service:AVTransport_scpd.xml</SCPDURL>
                <eventSubURL>_urn:schemas-upnp-org:service:AVTransport_event</eventSubURL>
            </service>
            <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
                <SCPDURL>_urn:schemas-upnp-org:service:ConnectionManager_scpd.xml</SCPDURL>
                <controlURL>_urn:schemas-upnp-org:service:ConnectionManager_control</controlURL>
                <eventSubURL>_urn:schemas-upnp-org:service:ConnectionManager_event</eventSubURL>
            </service>
            <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <SCPDURL>_urn:schemas-upnp-org:service:RenderingControl_scpd.xml</SCPDURL>
                <controlURL>_urn:schemas-upnp-org:service:RenderingControl_control</controlURL>
                <eventSubURL>_urn:schemas-upnp-org:service:RenderingControl_event</eventSubURL>
            </service>
            <service>
                <serviceType>urn:mi-com:service:RController:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RController</serviceId>
                <SCPDURL> </SCPDURL>
                <controlURL>_urn:schemas-upnp-org:service:RenderingControl_control</controlURL>
                <eventSubURL>_urn:schemas-upnp-org:service:RenderingControl_event</eventSubURL>
            </service>
        </serviceList>
        <av:X_RController_DeviceInfo xmlns:av="urn:mi-com:av">
            <av:X_RController_Version>1.0</av:X_RController_Version>
            <av:X_RController_ServiceList>
                <av:X_RController_Service>
                    <av:X_RController_ServiceType>controller</av:X_RController_ServiceType>
                    <av:X_RController_ActionList_URL>192.168.100.114:6095/</av:X_RController_ActionList_URL>
                </av:X_RController_Service>
                <av:X_RController_Service>
                    <av:X_RController_ServiceType>data</av:X_RController_ServiceType>
                    <av:X_RController_ActionList_URL>http://api.tv.duokanbox.com/bolt/3party/</av:X_RController_ActionList_URL>
                </av:X_RController_Service>
            </av:X_RController_ServiceList>
        </av:X_RController_DeviceInfo>
    </device>
    <URLBase>http://192.168.100.114:49152</URLBase>
</root>
*/

// ignore_for_file: non_constant_identifier_names

part of 'lib.dart';

/// The discover device
final class Device {
  /// The device's client
  final Client client;

  /// The device's spec
  final DeviceSpec spec;

  Device._(this.client, this.spec);

  /// The factory method create
  factory Device.create(Client client, XmlDocument xml, String baseUrl) {
    return Device._(client, DeviceSpec.fromXml(xml, baseUrl));
  }

  late Map<String, Service> _servicesMap;
  Service? _avTransportService;
  Service? _renderingControlService;
  Service? _connectionManagerService;

  /// Get current device AVTransport service
  Service? get avTransportService => _avTransportService;

  /// Get current device RenderingControl service
  Service? get renderingControlService => _renderingControlService;

  /// Get current device ConnectionManagerService service
  Service? get connectionManagerService => _connectionManagerService;

  /// Get current device provides service
  Service? getService(String name) => _servicesMap[name];

  /// Get current device provides service list
  List<Service> get services => _servicesMap.values.toList();

  bool get _realDevice => _avTransportService != null;

  /// Check current device is alive
  Future<bool> alive() async {
    final code = await Http.head(client.LOCATION);
    return code >= 200 && code < 300;
  }

  Future<void> _init() async {
    _servicesMap = <String, Service>{};
    for (var spec in spec.serviceSpecs) {
      if (RegExp(r':(AVTransport|RenderingControl|ConnectionManager):\d+$').hasMatch(spec.serviceType)) {
        var service = Service.build(spec);
        await service._init();
        _servicesMap[spec.serviceId] = service;
        if (spec.serviceType.contains(':AVTransport:')) _avTransportService = service;
        if (spec.serviceType.contains(':RenderingControl:')) _renderingControlService = service;
        if (spec.serviceType.contains(':ConnectionManager:')) _connectionManagerService = service;
      }
    }
  }

  bool _supported(String serviceId) =>
      _svcMap[_avt] == serviceId ||
      _svcMap[_rc] == serviceId ||
      _svcMap[_cm] == serviceId;
}

final _avt = 'AVTransport';
final _rc = 'RenderingControl';
final _cm = 'ConnectionManager';
final _svcMap = {
  'AVTransport': 'urn:upnp-org:serviceId:AVTransport',
  'ConnectionManager': 'urn:upnp-org:serviceId:ConnectionManager',
  'RenderingControl': 'urn:upnp-org:serviceId:RenderingControl',
  'RController': 'urn:upnp-org:serviceId:RController'
};

/// The discover device spec
final class DeviceSpec {
  /// The urn of this type of device
  final String deviceType;

  /// The url for presentation
  final String presentationUrl;

  /// The user friendly name
  final String friendlyName;

  /// The manufacturer of this device
  final String manufacturer;

  /// The URL to the manufacturer site
  final String manufacturerUrl;

  /// The long user-friendly title
  final String modelDescription;

  /// The name of this model
  final String modelName;

  /// The name of this model
  final String modelURL;

  /// The name of this model
  final String UPC;

  /// The universal device name of this device
  final String udn;

  /// The uuid extracted from the [udn]
  final String uuid;

  /// The base url of this device
  final String URLBase;

  /// The device provides service spec list
  final List<ServiceSpec> serviceSpecs;

  /// The device provides icon spec list, ignored
  final List<IconSpec> iconSpecs;

  DeviceSpec(
      this.deviceType,
      this.presentationUrl,
      this.friendlyName,
      this.manufacturer,
      this.manufacturerUrl,
      this.modelDescription,
      this.modelName,
      this.modelURL,
      this.UPC,
      this.udn,
      this.uuid,
      this.URLBase,
      this.serviceSpecs,
      this.iconSpecs);

  /// Prefix-independent parsing; embedded MediaRenderers are valid too.
  factory DeviceSpec.fromXml(XmlDocument xml, String location) {
    String value(XmlElement parent, String name) => parent.childElements
        .where((e) => e.name.local == name).map((e) => e.innerText.trim()).firstOrNull ?? '';
    final candidates = xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'device');
    final device = candidates.where((d) => d.childElements
        .where((e) => e.name.local == 'serviceList').expand((e) => e.childElements)
        .any((s) => value(s, 'serviceType').contains(':AVTransport:'))).firstOrNull;
    if (device == null) throw const CastProtocolException('该设备没有媒体播放服务');
    final baseText = xml.rootElement.childElements.where((e) => e.name.local == 'URLBase')
        .map((e) => e.innerText.trim()).firstOrNull ?? '';
    final base = Uri.parse(baseText.isEmpty ? location : baseText);
    if (!['http', 'https'].contains(base.scheme) || base.host.isEmpty) {
      throw const CastProtocolException('设备描述中的 URLBase 无效');
    }
    final services = device.childElements.where((e) => e.name.local == 'serviceList')
        .expand((e) => e.childElements).where((e) => e.name.local == 'service')
        .where((e) => value(e, 'controlURL').isNotEmpty).map((e) {
      final control = value(e, 'controlURL');
      final scpd = value(e, 'SCPDURL');
      return ServiceSpec(base.toString(), value(e, 'serviceType'), value(e, 'serviceId'),
          control, scpd, value(e, 'eventSubURL'), base.resolve(control).toString(),
          scpd.isEmpty ? '' : base.resolve(scpd).toString());
    }).toList();
    final udn = value(device, 'UDN');
    return DeviceSpec(value(device, 'deviceType'), value(device, 'presentationURL'),
      value(device, 'friendlyName'), value(device, 'manufacturer'), value(device, 'manufacturerURL'),
      value(device, 'modelDescription'), value(device, 'modelName'), value(device, 'modelURL'),
      value(device, 'UPC'), udn, udn.isEmpty ? location : udn.replaceFirst('uuid:', ''),
      base.toString(), services, []);
  }
}
