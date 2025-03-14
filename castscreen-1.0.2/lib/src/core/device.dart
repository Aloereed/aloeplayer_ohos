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
    // 打印xml
    print(xml.toXmlString(pretty: true));
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

  bool get _realDevice => _servicesMap.isNotEmpty;

  /// Check current device is alive
  Future<bool> alive() async {
    return await Http.head(spec.URLBase) == 200;
  }

  Future<void> _init() async {
    _servicesMap = <String, Service>{};
    for (var spec in spec.serviceSpecs) {
      if (_supported(spec.serviceId)) {
        var service = Service.build(spec);
        await service._init();
        _servicesMap[spec.serviceId] = service;
      }
    }
    if (_servicesMap.isNotEmpty) {
      _avTransportService = _servicesMap[_svcMap[_avt]];
      _renderingControlService = _servicesMap[_svcMap[_rc]];
      _connectionManagerService = _servicesMap[_svcMap[_cm]];
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

  /// The factory method fromXml
  factory DeviceSpec.fromXml(XmlDocument xml, String baseUrl) {
    print("[cast] base url: $baseUrl");
    final deviceType = xml.xpathEvaluate(_xpath('deviceType')).string;
    final presentationURL = xml.xpathEvaluate(_xpath('presentationURL')).string;
    final friendlyName = xml.xpathEvaluate(_xpath('friendlyName')).string;
    final manufacturer = xml.xpathEvaluate(_xpath('manufacturer')).string;
    final manufacturerURL = xml.xpathEvaluate(_xpath('manufacturerURL')).string;
    final modelDescription =
        xml.xpathEvaluate(_xpath('modelDescription')).string;
    final modelName = xml.xpathEvaluate(_xpath('modelName')).string;
    final modelURL = xml.xpathEvaluate(_xpath('modelURL')).string;
    final UPC = xml.xpathEvaluate(_xpath('UPC')).string;
    final UDN = xml.xpathEvaluate(_xpath('UDN')).string;
    final uuid = UDN.startsWith('uuid:') ? UDN.split(':')[1] : '';

    // 尝试获取URLBase，如果不存在则使用传入的baseUrl
    String URLBase = xml.xpathEvaluate('/root/URLBase/text()').string;
    if (URLBase == null || URLBase.isEmpty) {
      URLBase = baseUrl;
    }
    if(!URLBase.endsWith('/')){
      URLBase += '/';
    }

    final length = xml.xpath('/root/device/serviceList/service').length;
    final iconLength = xml.xpath('/root/device/iconList/icon').length;

    return DeviceSpec(
        deviceType,
        presentationURL,
        friendlyName,
        manufacturer,
        manufacturerURL,
        modelDescription,
        modelName,
        modelURL,
        UPC,
        UDN,
        uuid,
        URLBase,
        List.generate(
            length, (index) => ServiceSpec.fromXml(xml, index + 1, URLBase)),
        List.generate(
            iconLength, (index) => IconSpec.fromXml(xml, index + 1)));
  }

  static String _xpath(String name) => '/root/device/$name/text()';
}
