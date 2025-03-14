/*
<action>
    <name>GetCurrentTransportActions</name>
    <argumentList>
        <argument>
            <name>InstanceID</name>
            <direction>in</direction>
            <relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable>
        </argument>
        <argument>
            <name>Actions</name>
            <direction>out</direction>
            <relatedStateVariable>CurrentTransportActions</relatedStateVariable>
        </argument>
    </argumentList>
</action>
*/

part of 'lib.dart';

/// The device service action spec
final class ActionSpec {
  /// The action name
  final String name;

  /// The action argument list
  final List<ActionArgumentSpec> argumentList;

  const ActionSpec(this.name, this.argumentList);

  /// The factory method fromXml
  factory ActionSpec.fromXml(
    XmlDocument xml,
    int index,
  ) {
    final name =
        xml.xpathEvaluate('/scpd/actionList/action[$index]/name/text()').string;
    final length = xml
        .xpath('/scpd/actionList/action[$index]/argumentList/argument')
        .length;
    return ActionSpec(
        name,
        List.generate(
            length,
            (subIndex) =>
                ActionArgumentSpec.fromXml(xml, index, subIndex + 1)));
  }
}

/// The service action argument spec
final class ActionArgumentSpec {
  /// The action argument name
  /// <name>InstanceID</name>
  final String name;

  /// The action argument direction. Option values: in | out
  /// <direction>in</direction>
  final String direction;

  /// The action argument related state variable
  /// <relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable>
  final String relatedStateVariable;

  const ActionArgumentSpec(
      this.name, this.direction, this.relatedStateVariable);

  /// The factory method fromXml
  factory ActionArgumentSpec.fromXml(XmlDocument xml, int pIndex, int index) {
    final name = xml.xpathEvaluate(_xpath(pIndex, index, 'name')).string;
    final direction =
        xml.xpathEvaluate(_xpath(pIndex, index, 'direction')).string;
    final relatedStateVariable =
        xml.xpathEvaluate(_xpath(pIndex, index, 'relatedStateVariable')).string;
    return ActionArgumentSpec(name, direction, relatedStateVariable);
  }

  static String _xpath(int pIndex, int index, String name) =>
      '/scpd/actionList/action[$pIndex]/argumentList/argument[$index]/$name/text()';
}
