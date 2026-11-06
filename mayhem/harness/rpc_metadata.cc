// Fuzzes deserialization of the RPC wire metadata structs (what a Thrift server parses from every
// incoming rocket frame) in the Compact and Binary protocols. Byte 0 selects the struct and
// protocol; the rest is the payload.
#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>

#include <folly/Range.h>
#include <thrift/lib/cpp2/protocol/Serializer.h>
#include <thrift/lib/thrift/gen-cpp2/RpcMetadata_types.h>

using namespace apache::thrift;

template <class Ser, class T>
static void run(folly::ByteRange payload) {
  T obj;
  try {
    Ser::deserialize(payload, obj);
    (void)Ser::template serialize<std::string>(obj);
  } catch (const std::exception&) {
  }
}

template <class T>
static void run_all(uint8_t proto, folly::ByteRange payload) {
  if (proto & 1) {
    run<BinarySerializer, T>(payload);
  } else {
    run<CompactSerializer, T>(payload);
  }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) {
    return -1;
  }
  uint8_t sel = data[0];
  folly::ByteRange payload(data + 1, size - 1);
  switch ((sel >> 1) % 8) {
    case 0: run_all<RequestRpcMetadata>(sel, payload); break;
    case 1: run_all<ResponseRpcMetadata>(sel, payload); break;
    case 2: run_all<RequestSetupMetadata>(sel, payload); break;
    case 3: run_all<ServerPushMetadata>(sel, payload); break;
    case 4: run_all<ClientPushMetadata>(sel, payload); break;
    case 5: run_all<StreamPayloadMetadata>(sel, payload); break;
    case 6: run_all<ResponseRpcError>(sel, payload); break;
    default: run_all<HeadersPayloadContent>(sel, payload); break;
  }
  return 0;
}
