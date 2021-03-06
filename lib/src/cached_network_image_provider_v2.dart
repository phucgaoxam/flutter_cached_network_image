import 'dart:async' show Future;
import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' as ui show instantiateImageCodec, Codec;

import 'package:cached_network_image/src/image_provider/cached_network_image_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

typedef CompressCallback = Future<File> Function(File);

class CachedNetworkImageProviderV2 extends ImageProvider<CachedNetworkImageProviderV2> {
  /// Creates an ImageProvider which loads an image from the [url], using the [scale].
  /// When the image fails to load [errorListener] is called.
  const CachedNetworkImageProviderV2(
    this.url, {
    this.scale: 1.0,
    this.errorListener,
    this.headers,
    this.cacheManager,
    this.compressCallback,
    this.isDeleteSourceCached = false,
  })  : assert(url != null),
        assert(scale != null);

  final BaseCacheManager? cacheManager;

  /// Web url of the image to load
  final String? url;

  /// Scale of the image
  final double? scale;

  /// Listener to be called when images fails to load.
  final ErrorListener? errorListener;

  // Set headers for the image provider, for example for authentication
  final Map<String, String>? headers;

  final CompressCallback? compressCallback;

  final bool isDeleteSourceCached;

  @override
  Future<CachedNetworkImageProviderV2> obtainKey(ImageConfiguration configuration) {
    return new SynchronousFuture<CachedNetworkImageProviderV2>(this);
  }

  @override
  ImageStreamCompleter load(CachedNetworkImageProviderV2 key, DecoderCallback decode) {
    return new MultiFrameImageStreamCompleter(
      codec: _loadAsync(key),
      scale: key.scale,
// TODO enable information collector on next stable release of flutter
//      informationCollector: () sync* {
//        yield DiagnosticsProperty<ImageProvider>(
//          'Image provider: $this \n Image key: $key',
//          this,
//          style: DiagnosticsTreeStyle.errorProperty,
//        );
//      },
    );
  }

  Future<ui.Codec> _loadAsync(CachedNetworkImageProviderV2 key) async {
    var mngr = cacheManager ?? DefaultCacheManager();
    var file = await mngr.getSingleFile(url, headers: headers);
    if (file == null) {
      if (errorListener != null) errorListener();
      return Future<ui.Codec>.error("Couldn't download or retrieve file.");
    }
    if (compressCallback != null) {
      file = await _compress(file, mngr);
      if (file == null) {
        if (errorListener != null) errorListener();
        return Future<ui.Codec>.error("Image compression failed.");
      }
    }
    return await _loadAsyncFromFile(key, file, mngr);
  }

  Future<ui.Codec> _loadAsyncFromFile(CachedNetworkImageProviderV2 key, File? file, BaseCacheManager? mngr) async {
    assert(key == this);

    final Uint8List bytes = await file.readAsBytes();

    if (bytes.lengthInBytes == 0) {
      if (errorListener != null) errorListener();
      try {
        mngr.removeFile(url);
      } catch (ex) {}
      throw new Exception("File was empty");
    }
    return await ui.instantiateImageCodec(bytes);
  }

  Future<File> _compress(File? file, BaseCacheManager? mngr) async {
    var tempUrl = "${url}temp";
    FileInfo fileInfo = await mngr.getFileFromCache(tempUrl);
    var result;
    if (fileInfo == null) {
      result = await compressCallback(file);
      mngr.putFile(tempUrl, result.readAsBytesSync());
      if (isDeleteSourceCached) {
        await mngr.removeFile(url);
      }
    } else {
      result = fileInfo.file;
    }
    return result;
  }

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) return false;
    final CachedNetworkImageProviderV2 typedOther = other;
    return url == typedOther.url && scale == typedOther.scale;
  }

  @override
  int get hashCode => hashValues(url, scale);

  @override
  String toString() => '$runtimeType("$url", scale: $scale)';
}
