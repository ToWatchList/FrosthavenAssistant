import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:multicast_dns/src/constants.dart';
import 'package:multicast_dns/src/resource_record.dart';

class Bonjour {
  RawDatagramSocket? _socket;

  Future<void> advertise(String ip, int port) async {
    // Stop any existing advertising.
    stop();

    const String serviceName = '_frosthaven._tcp.local';
    final String serverName = 'Frosthaven Assistant Server.$serviceName';

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, mDnsPort);
    _socket!.joinMulticast(mDnsAddressIPv4);

    final PtrResourceRecord ptr = PtrResourceRecord(
      serviceName,
      3600,
      domainName: serverName,
    );

    final SrvResourceRecord srv = SrvResourceRecord(
      serverName,
      3600,
      port: port,
      target: ip,
      weight: 0,
      priority: 0,
    );

    final IPAddressResourceRecord ipAddress = IPAddressResourceRecord(
      ip,
      3600,
      address: InternetAddress(ip),
    );

    final List<int> packet = _buildResponse([ptr, srv, ipAddress]);
    _socket!.send(packet, mDnsAddressIPv4, mDnsPort);
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  List<int> _buildResponse(List<ResourceRecord> records) {
    final writer = _MDnsWriter(isQuery: false);
    writer.writeRecords(records);
    return writer.toUint8List();
  }
}

class _MDnsWriter {
  _MDnsWriter({this.isQuery = true}) {
    // ID is always 0
    _byteData.setUint16(0, 0);
    // Flags
    _byteData.setUint16(2, isQuery ? 0 : 0x8400); // Authoritative answer
    // Question count
    _byteData.setUint16(4, 0);
    // Answer count
    _byteData.setUint16(6, 0);
    // Authority count
    _byteData.setUint16(8, 0);
    // Additional count
    _byteData.setUint16(10, 0);
  }

  final bool isQuery;
  final Uint8List _data = Uint8List(4096);
  late final ByteData _byteData = ByteData.view(_data.buffer);
  int _offset = 12;
  final Map<String, int> _fqdnOffsets = <String, int>{};

  void writeFQDN(String fqdn) {
    if (_fqdnOffsets.containsKey(fqdn)) {
      final int fqdnOffset = _fqdnOffsets[fqdn]!;
      _byteData.setUint16(_offset, 0xc000 | fqdnOffset);
      _offset += 2;
      return;
    }

    _fqdnOffsets[fqdn] = _offset;
    final List<String> parts = fqdn.split('.');
    for (final String part in parts) {
      final List<int> partBytes = utf8.encode(part);
      _data[_offset++] = partBytes.length;
      _data.setRange(_offset, _offset + partBytes.length, partBytes);
      _offset += partBytes.length;
    }
    _data[_offset++] = 0;
  }

  void writeRecord(ResourceRecord record) {
    writeFQDN(record.fullyQualifiedName);
    _byteData.setUint16(_offset, record.resourceRecordType);
    _offset += 2;
    _byteData.setUint16(_offset, ResourceRecordClass.internet | 0x8000); // Cache flush
    _offset += 2;
    _byteData.setUint32(_offset, record.ttl);
    _offset += 4;

    final int dataLengthOffset = _offset;
    _offset += 2;

    final int dataStartOffset = _offset;

    if (record is IPAddressResourceRecord) {
      final List<int> addressBytes = record.address.rawAddress;
      _data.setRange(_offset, _offset + addressBytes.length, addressBytes);
      _offset += addressBytes.length;
    } else if (record is PtrResourceRecord) {
      writeFQDN(record.domainName);
    } else if (record is SrvResourceRecord) {
      _byteData.setUint16(_offset, record.priority);
      _offset += 2;
      _byteData.setUint16(_offset, record.weight);
      _offset += 2;
      _byteData.setUint16(_offset, record.port);
      _offset += 2;
      writeFQDN(record.target);
    } else if (record is TxtResourceRecord) {
      final List<int> textBytes = utf8.encode(record.text);
      _data[_offset++] = textBytes.length;
      _data.setRange(_offset, _offset + textBytes.length, textBytes);
      _offset += textBytes.length;
    }

    final int dataLength = _offset - dataStartOffset;
    _byteData.setUint16(dataLengthOffset, dataLength);
  }

  void writeRecords(List<ResourceRecord> records) {
    _byteData.setUint16(6, records.length);
    for (final ResourceRecord record in records) {
      writeRecord(record);
    }
  }

  Uint8List toUint8List() {
    return Uint8List.view(_data.buffer, 0, _offset);
  }
}
