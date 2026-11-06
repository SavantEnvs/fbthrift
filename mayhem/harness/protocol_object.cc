// Fuzzes schemaless Thrift decoding: parse arbitrary bytes into a protocol::Object (the dynamic
// value used by Any, patches and field masks) with the Compact and Binary readers, then re-encode.
#include <cstddef>
#include <cstdint>
#include <exception>

#include <folly/io/IOBuf.h>
#include <folly/io/IOBufQueue.h>
#include <thrift/lib/cpp2/protocol/BinaryProtocol.h>
#include <thrift/lib/cpp2/protocol/CompactProtocol.h>
#include <thrift/lib/cpp2/protocol/Object.h>

using namespace apache::thrift;

template <class Reader, class Writer>
static void run(const folly::IOBuf& buf) {
  try {
    auto obj = protocol::parseObject<Reader>(buf);
    (void)protocol::serializeObject<Writer>(obj);
  } catch (const std::exception&) {
  }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) {
    return -1;
  }
  auto buf = folly::IOBuf::wrapBuffer(data + 1, size - 1);
  if (data[0] & 1) {
    run<BinaryProtocolReader, BinaryProtocolWriter>(*buf);
  } else {
    run<CompactProtocolReader, CompactProtocolWriter>(*buf);
  }
  return 0;
}
