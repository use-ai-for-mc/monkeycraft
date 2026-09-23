package com.chenweikeng.monkeycraft.utils;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class TailnetHttpsTest {
  @Test
  void selectsOnlyTheHttpsRootForTheActualGamePort() {
    String config =
        """
        {"TCP":{"443":{"HTTPS":true},"8443":{"HTTPS":true}},"Web":{
          "host.tail.ts.net:443":{"Handlers":{"/":{"Proxy":"http://localhost:8081"}}},
          "host.tail.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9602"}}}
        }}
        """;
    assertEquals(8443, TailnetHttps.parseServeHttpsPort(config, "host.tail.ts.net", 9602));
    assertEquals(0, TailnetHttps.parseServeHttpsPort(config, "host.tail.ts.net", 9600));
  }

  @Test
  void rejectsHttpOtherHostsAndSubpathProxies() {
    String template =
        """
        {"TCP":{"8443":{%s}},"Web":{"%s:8443":{"Handlers":{"/":{"Proxy":"%s"}}}}}
        """;
    assertEquals(
        0,
        TailnetHttps.parseServeHttpsPort(
            template.formatted("\"HTTP\":true", "host.tail.ts.net", "http://127.0.0.1:9600"),
            "host.tail.ts.net",
            9600));
    assertEquals(
        0,
        TailnetHttps.parseServeHttpsPort(
            template.formatted("\"HTTPS\":true", "host.tail.ts.net.evil", "http://127.0.0.1:9600"),
            "host.tail.ts.net",
            9600));
    assertEquals(
        0,
        TailnetHttps.parseServeHttpsPort(
            template.formatted("\"HTTPS\":true", "host.tail.ts.net", "http://127.0.0.1:9600/other"),
            "host.tail.ts.net",
            9600));
    assertEquals(
        0,
        TailnetHttps.parseServeHttpsPort(
            template.formatted("\"HTTPS\":true", "host.tail.ts.net", "http://remote:9600"),
            "host.tail.ts.net",
            9600));
  }

  @Test
  void malformedOrUnconfiguredServeDoesNotAdvertiseAnAddress() {
    assertEquals(0, TailnetHttps.parseServeHttpsPort("{}", "host.tail.ts.net", 9600));
    assertEquals(0, TailnetHttps.parseServeHttpsPort("not json", "host.tail.ts.net", 9600));
  }
}
