import 'package:flutter/painting.dart';

ImageProvider<Object> photoSource(String source) =>
    source.startsWith('https://') || source.startsWith('http://')
    ? NetworkImage(source)
    : AssetImage(source);
