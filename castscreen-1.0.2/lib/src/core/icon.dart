/*
<icon>
  <mimetype>image/format</mimetype>
  <width>horizontal pixels</width>
  <height>vertical pixels</height>
  <depth>color depth</depth>
  <url>URL to icon</url>
</icon>
*/

part of 'lib.dart';

/// The device icon spec
final class IconSpec {
  /// The mimetype of this icon, always "image/<format>" like "image/png"
  final String mimetype;

  /// The amount of horizontal pixels
  final int width;

  /// The amount of vertical pixels
  final int height;

  /// The color depth of this image
  final int depth;

  /// The url to this icon
  final String url;

  const IconSpec(this.mimetype, this.width, this.height, this.depth, this.url);

  /// The factory method fromXml
  factory IconSpec.fromXml(XmlDocument xml, int index) {
    final mimetype = xml.xpathEvaluate(_xpath(index, 'mimetype')).string;
    final width = xml.xpathEvaluate(_xpath(index, 'width')).number.toInt();
    final height = xml.xpathEvaluate(_xpath(index, 'height')).number.toInt();
    final depth = xml.xpathEvaluate(_xpath(index, 'depth')).number.toInt();
    final url = xml.xpathEvaluate(_xpath(index, 'url')).string;
    return IconSpec(mimetype, width, height, depth, url);
  }

  static String _xpath(int index, String name) =>
      '/root/device/iconList/icon[$index]/$name/text()';
}
