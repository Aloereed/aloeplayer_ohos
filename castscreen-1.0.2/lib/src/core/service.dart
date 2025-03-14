/*
<service>
  <serviceType>urn:schemas-upnp-org:service:serviceType:v</serviceType>
  <serviceId>urn:upnp-org:serviceId:serviceID</serviceId>
  <SCPDURL>URL to service description</SCPDURL>
  <controlURL>URL for control</controlURL>
  <eventSubURL>URL for eventing</eventSubURL>
</service>
*/

// ignore_for_file: non_constant_identifier_names

part of 'lib.dart';

/// The device service controller
final class Service {
  /// The device service spec
  final ServiceSpec spec;
  Service._(this.spec);
  factory Service.build(ServiceSpec spec) {
    return Service._(spec);
  }

  late Map<String, ActionSpec> _actionsMap;

  Future<void> _init() async {
    spec.actionList = <ActionSpec>[];
    _actionsMap = <String, ActionSpec>{};
    final resp = await Http.get(spec.scpdReqURL, ScpdServiceSpec.fromXml);
    spec.actionList.addAll(resp.data.actionList);
    for (var actionSpec in spec.actionList) {
      _actionsMap[actionSpec.name] = actionSpec;
    }
  }

  /// Invoke a service action, and returns a generics type
  Future<OUTPUT> invoke<INPUT, OUTPUT>(
    String action,
    INPUT input,
    Map<String, String> Function(INPUT input) inputConvertor,
    OUTPUT Function(Map<String, String>) outputConvertor,
  ) async {
    final xmlBody = _buildXml(action, inputConvertor(input));
    final resp = await Http.post(
      spec.controlReqURL,
      (xml) => _parseXml(xml, action),
      body: xmlBody,
      headers: _headers(spec, action),
    );
    return Future.value(outputConvertor(resp.data));
  }

  /// Invoke a service action, and returns a map
  Future<Map<String, String>> invokeMap(
          String action, Map<String, String> input) async =>
      invoke<Map<String, String>, Map<String, String>>(
        action,
        input,
        (Map<String, String> m) => m,
        (Map<String, String> m) => m,
      );

  String _buildXml(String action, Map<String, String> arguments) {
    final xb = XmlBuilder();
    xb.processing('xml', 'version="1.0"');
    xb.element('s:Envelope', nest: () {
      xb.attribute('xmlns:s', 'http://schemas.xmlsoap.org/soap/envelope/');
      xb.attribute(
          's:encodingStyle', 'http://schemas.xmlsoap.org/soap/encoding/');
      xb.element('s:Body', nest: () {
        xb.element('u:$action', nest: () {
          xb.attribute('xmlns:u', spec.serviceType);
          arguments.forEach((k, v) {
            xb.element(k, nest: v);
          });
        });
      });
    });
    return xb.buildDocument().toXmlString();
  }

  Map<String, String> _parseXml(XmlDocument xml, String action) {
    final outArgs = _actionsMap[action]!
        .argumentList
        .where((arg) => arg.direction == 'out');
    final m = <String, String>{};
    for (var arg in outArgs) {
      m[arg.name] = xml.xpathEvaluate(_xpath(action, arg.name)).string;
    }
    return m;
  }

  static Map<String, String> _headers(ServiceSpec spec, String action) {
    return {
      "Content-Type": "text/xml; charset=utf-8",
      "SOAPAction": '"${spec.serviceType}#$action"'
    };
  }

  static String _xpath(String action, String argument) =>
      '/s:Envelope/s:Body/u:${action}Response/$argument/text()';
}

/// The device service spec.
final class ServiceSpec {
  /// The device base url
  final String URLBase;

  /// The urn of this services type
  final String serviceType;

  /// The urn of this services id
  final String serviceId;

  /// The url to control this service
  final String controlURL;

  /// The url this services description
  final String SCPDURL;

  /// The url to subscribe to events
  final String eventSubURL;

  /// The url to control req
  final String controlReqURL;

  /// The url to scpd req
  final String scpdReqURL;

  /// The device service action list
  late List<ActionSpec> actionList;

  ServiceSpec(
    this.URLBase,
    this.serviceType,
    this.serviceId,
    this.controlURL,
    this.SCPDURL,
    this.eventSubURL,
    this.controlReqURL,
    this.scpdReqURL,
  );

  /// The factory method fromXml
  factory ServiceSpec.fromXml(XmlDocument xml, int index, String baseUrl) {
    final serviceType = xml.xpathEvaluate(_xpath(index, 'serviceType')).string;
    final serviceId = xml.xpathEvaluate(_xpath(index, 'serviceId')).string;
    final controlURL = xml.xpathEvaluate(_xpath(index, 'controlURL')).string;
    final SCPDURL = xml.xpathEvaluate(_xpath(index, 'SCPDURL')).string;
    final eventSubURL = xml.xpathEvaluate(_xpath(index, 'eventSubURL')).string;

    // 使用传入的baseUrl作为基础URL
    final controlReqURL = baseUrl + ((controlURL.startsWith('/'))? controlURL.substring(1): controlURL);

    print("[cast] controlReqURL: $controlReqURL");

    final scpdReqURL = baseUrl + ((SCPDURL.startsWith('/'))? SCPDURL.substring(1): SCPDURL);
    print("[cast] scpdReqURL: $scpdReqURL");

    return ServiceSpec(
      baseUrl,
      serviceType,
      serviceId,
      controlURL,
      SCPDURL,
      eventSubURL,
      controlReqURL,
      scpdReqURL,
    );
  }

  static String _xpath(int index, String name) =>
      '/root/device/serviceList/service[$index]/$name/text()';
}

final class ScpdServiceSpec {
  final List<ActionSpec> actionList;
  const ScpdServiceSpec(this.actionList);
  factory ScpdServiceSpec.fromXml(XmlDocument xml) {
    final length = xml.xpath('/scpd/actionList/action').length;
    return ScpdServiceSpec(
      List.generate(length, (index) => ActionSpec.fromXml(xml, index + 1)),
    );
  }
}
