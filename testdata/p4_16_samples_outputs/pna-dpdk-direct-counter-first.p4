#include <core.p4>
#include <pna.p4>

typedef bit<48> EthernetAddress;
const bit<8> ETHERNET_HEADER_LEN = 8w14;
header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16>         etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

struct empty_metadata_t {
}

struct main_metadata_t {
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t     ipv4;
}

typedef bit<48> ByteCounter_t;
typedef bit<32> PacketCounter_t;
typedef bit<80> PacketByteCounter_t;
typedef bit<16> FlowIdx_t;
const bit<32> IPV4_HOST_TABLE_MAX_ENTRIES = 32w1024;
parser MainParserImpl(packet_in pkt, out headers_t hdr, inout main_metadata_t main_meta, in pna_main_parser_input_metadata_t istd) {
    state start {
        pkt.extract<ethernet_t>(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            16w0x800: parse_ipv4;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract<ipv4_t>(hdr.ipv4);
        transition accept;
    }
}

control PreControlImpl(in headers_t hdr, inout main_metadata_t meta, in pna_pre_input_metadata_t istd, inout pna_pre_output_metadata_t ostd) {
    apply {
    }
}

control MainControlImpl(inout headers_t hdr, inout main_metadata_t user_meta, in pna_main_input_metadata_t istd, inout pna_main_output_metadata_t ostd) {
    DirectCounter<ByteCounter_t>(PNA_CounterType_t.BYTES) per_prefix_bytes_count;
    DirectCounter<PacketByteCounter_t>(PNA_CounterType_t.PACKETS_AND_BYTES) per_prefix_pkt_bytes_count;
    DirectCounter<PacketCounter_t>(PNA_CounterType_t.PACKETS) per_prefix_pkt_count;
    action count() {
        per_prefix_pkt_count.count();
    }
    action bytecount() {
        per_prefix_bytes_count.count(32w1024);
    }
    action pktbytecount() {
        per_prefix_pkt_bytes_count.count(32w1024);
    }
    table ipv4_host {
        key = {
            hdr.ipv4.dstAddr: exact @name("hdr.ipv4.dstAddr");
        }
        actions = {
            count();
        }
        const default_action = count();
        size = 32w1024;
        pna_direct_counter = per_prefix_pkt_count;
    }
    table ipv4_host_byte_count {
        key = {
            hdr.ipv4.dstAddr: exact @name("hdr.ipv4.dstAddr");
        }
        actions = {
            bytecount();
        }
        const default_action = bytecount();
        size = 32w1024;
        pna_direct_counter = per_prefix_bytes_count;
    }
    table ipv4_host_pkt_byte_count {
        key = {
            hdr.ipv4.dstAddr: exact @name("hdr.ipv4.dstAddr");
        }
        actions = {
            pktbytecount();
        }
        const default_action = pktbytecount();
        size = 32w1024;
        pna_direct_counter = per_prefix_pkt_bytes_count;
    }
    apply {
        ipv4_host.apply();
        ipv4_host_byte_count.apply();
        ipv4_host_pkt_byte_count.apply();
    }
}

control MainDeparserImpl(packet_out pkt, in headers_t hdr, in main_metadata_t user_meta, in pna_main_output_metadata_t ostd) {
    apply {
        pkt.emit<ethernet_t>(hdr.ethernet);
        pkt.emit<ipv4_t>(hdr.ipv4);
    }
}

PNA_NIC<headers_t, main_metadata_t, headers_t, main_metadata_t>(MainParserImpl(), PreControlImpl(), MainControlImpl(), MainDeparserImpl()) main;
