library eventsource3.server;

export "src/event.dart";

import "dart:async";

import "package:logging/logging.dart" as log;

import "src/event.dart";
import "src/event_cache.dart";
import "src/proxy_sink.dart";

/// An EventSource publisher. It can manage different channels of events.
/// This class forms the backbone of an EventSource server. To actually serve
/// a web server, use this together with [shelf_eventsource] or another server
/// implementation.

class EventSourcePublisher {
  log.Logger? logger;
  EventCache? _cache;

  final _sink = StreamController<Event>(); // Replace the inheritance

  EventSourcePublisher({
    int cacheCapacity = 0,
    bool comparableIds = false,
    bool enableLogging = true,
  }) {
    if (cacheCapacity > 0) {
      _cache = new EventCache(cacheCapacity: cacheCapacity);
    }
    if (enableLogging) {
      logger = new log.Logger("EventSourceServer");
    }
  }

  Map<String, List<ProxySink>> _subsByChannel = {};

  /// Creates a Sink for the specified channel.
  Sink<Event> channel(String channel) => new ProxySink(
      onAdd: (e) => add(e, channels: [channel]),
      onClose: () => close(channels: [channel]));

  /// Add a publication to the specified channels.
  void add(Event event, {Iterable<String> channels = const [""]}) {
    for (String channel in channels) {
      List<ProxySink>? subs = _subsByChannel[channel];
      if (subs == null) {
        continue;
      }
      _logFiner(
          "Sending event on channel $channel to ${subs.length} subscribers.");
      for (var sub in subs) {
        sub.add(event);
      }
    }
    _cache?.add(event, channels);
  }

  /// Close the specified channels.
  void close({Iterable<String> channels = const [""]}) {
    for (String channel in channels) {
      List<ProxySink>? subs = _subsByChannel[channel];
      if (subs == null) {
        continue;
      }
      _logInfo("Closing channel $channel with ${subs.length} subscribers.");
      for (var sub in subs) {
        sub.close();
      }
    }
    _cache?.clear(channels);
  }

  /// Close all the open channels.
  void closeAllChannels() => close(channels: _subsByChannel.keys);

  void newSubscription({
    required void Function(Event) onEvent,
    required void Function() onClose,
    required String channel,
    String? lastEventId,
  }) {
    _logFine("New subscriber on channel $channel.");
    ProxySink<Event> sub = new ProxySink(onAdd: onEvent, onClose: onClose);
    _subsByChannel.putIfAbsent(channel, () => []).add(sub);
    if (_cache != null && lastEventId != null) {
      scheduleMicrotask(() {
        _logFine("Replaying events on channel $channel from id $lastEventId.");
        _cache!.replay(sub, lastEventId, channel);
      });
    }
  }

  void _logInfo(message) {
    logger?.log(log.Level.INFO, message);
  }

  void _logFine(message) {
    logger?.log(log.Level.FINE, message);
  }

  void _logFiner(message) {
    logger?.log(log.Level.FINER, message);
  }
}
