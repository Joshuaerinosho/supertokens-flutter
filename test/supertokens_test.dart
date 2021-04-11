import 'dart:convert';

@Timeout(const Duration(seconds: 60))
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supertokens/src/anti-csrf.dart';
import 'package:supertokens/src/id-refresh-token.dart';
import 'package:supertokens/supertokens.dart';
import 'package:http/http.dart' as http;

import 'test-utils.dart';

void main() {
  SuperTokensHttpClient networkClient =
      SuperTokensHttpClient.getInstance(http.Client());

  String loginAPIURL = "${SuperTokensTestUtils.testAPIBase}login";
  String refreshTokenUrl = "${SuperTokensTestUtils.testAPIBase}refresh";
  String userInfoAPIURL = "${SuperTokensTestUtils.testAPIBase}userInfo";
  String logoutAPIURL = "${SuperTokensTestUtils.testAPIBase}logout";
  String refreshCustomHeaderURL =
      "${SuperTokensTestUtils.testAPIBase}checkCustomHeader";

  int sessionExpiryCode = 401;

  Future<void> startST({
    int validity = 1,
    double? refreshValidity,
    bool disableAntiCSRF = false,
  }) async {
    await SuperTokensTestUtils.startSuperTokens(
        validity: validity,
        refreshValidity: refreshValidity,
        disableAntiCSRF: disableAntiCSRF);
  }

  Future<int> getRefreshTokenCounterUsingST() async {
    String refreshCounterAPIURL =
        "${SuperTokensTestUtils.testAPIBase}refreshCounter";
    http.Response response =
        await networkClient.get(Uri.parse(refreshCounterAPIURL));

    if (response.statusCode != 200) {
      throw Exception("Refresh counter API using ST failed");
    }

    Map<String, dynamic> responseBody = jsonDecode(response.body);
    return responseBody["counter"];
  }

  Future<void> _setUp() async {
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    SuperTokens.isInitCalled = false;
    await AntiCSRF.removeToken();
    await IdRefreshToken.removeToken();
    await SuperTokensTestUtils.beforeEachTest();
  }

  setUp(() {
    return _setUp();
  });

  tearDown(() async {
    return SuperTokensTestUtils.afterEachTest();
  });

  test("Test that requests fail when SuperTokens.initialise is not called",
      () async {
    try {
      await networkClient.post(Uri.parse(loginAPIURL));
    } on http.ClientException catch (e) {
      if (e.message !=
          "SuperTokens.initialise must be called before using SuperTokensHttpClient") {
        throw e;
      }
    } catch (e) {
      throw e;
    }
  });

  test("Test that multiple calls to SuperTokens.initialise work as expected",
      () async {
    await startST(validity: 5);

    try {
      SuperTokens.initialise(
          refreshTokenEndpoint: refreshTokenUrl,
          sessionExpiryStatusCode: sessionExpiryCode);

      SuperTokens.initialise(
          refreshTokenEndpoint: refreshTokenUrl,
          sessionExpiryStatusCode: sessionExpiryCode);
    } catch (e) {
      fail("Calling initialise more than once failed");
    }

    http.Response response = await networkClient.post(Uri.parse(loginAPIURL));
    if (response.statusCode != 200) {
      fail("Login API failed");
    }

    try {
      SuperTokens.initialise(
          refreshTokenEndpoint: refreshTokenUrl,
          sessionExpiryStatusCode: sessionExpiryCode);
    } catch (e) {
      fail("Calling initialise more than once failed");
    }

    http.Response userInfoResponse =
        await networkClient.get(Uri.parse(userInfoAPIURL));
    if (userInfoResponse.statusCode != 200) {
      fail("UserInfo API failed");
    }
  });

  test(
      "Test that the refresh endpoint gets set correctly when using a URL with no path",
      () {
    try {
      SuperTokens.initialise(refreshTokenEndpoint: "https://api.example.com");
    } catch (e) {
      fail("SuperTokens.initialise threw an error");
    }
    expect(SuperTokens.refreshTokenEndpoint,
        "https://api.example.com/session/refresh");
  });

  test(
      "Test that the refresh endpoint gets set correctly when using a URL with empty path",
      () {
    try {
      SuperTokens.initialise(refreshTokenEndpoint: "https://api.example.com/");
    } catch (e) {
      fail("SuperTokens.initialise threw an error");
    }
    expect(SuperTokens.refreshTokenEndpoint,
        "https://api.example.com/session/refresh");
  });

  test(
      "Test that the refresh endpoint gets set correctly when using a URL with a valid path",
      () {
    try {
      SuperTokens.initialise(
          refreshTokenEndpoint: "https://api.example.com/other/url");
    } catch (e) {
      fail("SuperTokens.initialise threw an error");
    }
    expect(
        SuperTokens.refreshTokenEndpoint, "https://api.example.com/other/url");
  });

  test(
      "Test that network requests without valid credentials throw session expired and do not trigger a call to the refresh endpoint",
      () async {
    await startST(validity: 3);

    try {
      SuperTokens.initialise(
          refreshTokenEndpoint: refreshTokenUrl,
          sessionExpiryStatusCode: sessionExpiryCode);
    } catch (e) {
      throw e;
    }

    try {
      http.Response response =
          await networkClient.get(Uri.parse(userInfoAPIURL));

      if (response.statusCode == 200) {
        fail("userInfo API succeeded when it should have failed");
      }

      if (response.statusCode != sessionExpiryCode) {
        fail("UserInfo status code did not match session expired");
      }
    } catch (e) {
      throw e;
    }
  });

  test("Test that the library works as expected when anti-csrf is disabled",
      () async {
    await startST(validity: 3, refreshValidity: 2, disableAntiCSRF: true);

    try {
      SuperTokens.initialise(
          refreshTokenEndpoint: refreshTokenUrl,
          sessionExpiryStatusCode: sessionExpiryCode);
    } catch (e) {
      throw e;
    }

    http.Response response = await networkClient.post(Uri.parse(loginAPIURL));

    if (response.statusCode != 200) {
      fail("Login API failed");
    }

    await Future.delayed(Duration(seconds: 5));

    http.Response userInfoResponse =
        await networkClient.get(Uri.parse(userInfoAPIURL));

    if (userInfoResponse.statusCode != 200) {
      fail("userInfo API failed");
    }

    int refreshCounter = await SuperTokensTestUtils.getRefreshTokenCounter();
    if (refreshCounter != 1) {
      fail("Unexpected counter value: was $refreshCounter extected 1");
    }

    http.Response logoutResponse =
        await networkClient.post(Uri.parse(logoutAPIURL));
    if (logoutResponse.statusCode != 200) {
      fail("Logout API failed");
    }

    expect(await SuperTokens.doesSessionExist(), false);
  });

  test(
      "Test that custom refresh headers are sent properly when calls to the refresh endpoint are triggered",
      () async {
    await startST(validity: 3);

    try {
      SuperTokens.initialise(
        refreshTokenEndpoint: refreshTokenUrl,
        sessionExpiryStatusCode: sessionExpiryCode,
        refreshAPICustomHeaders: {
          "testKey": "testValue",
        },
      );
    } catch (e) {
      fail("Error initialising SuperTokens");
    }

    http.Response loginResponse =
        await networkClient.post(Uri.parse(loginAPIURL));

    if (loginResponse.statusCode != 200) {
      fail("Login API failed");
    }

    String? idRefreshTokenBefore = await IdRefreshToken.getToken();
    await Future.delayed(Duration(seconds: 5));

    http.Response userInfoResponse =
        await networkClient.get(Uri.parse(userInfoAPIURL));

    if (userInfoResponse.statusCode != 200) {
      fail("UserInfo API failed");
    }

    String? idRefreshTokenAfter = await IdRefreshToken.getToken();

    if (idRefreshTokenBefore == idRefreshTokenAfter) {
      fail(
          "IdRefreshToken before and after are same, expected to be different");
    }

    http.Response refreshCustomHeaderResponse =
        await networkClient.get(Uri.parse(refreshCustomHeaderURL));

    print(refreshCustomHeaderResponse.statusCode);
    if (refreshCustomHeaderResponse.statusCode != 200) {
      fail("Refresh custom header call failed");
    }

    String refreshCustomHeaderResponseBody = refreshCustomHeaderResponse.body;

    if (refreshCustomHeaderResponseBody != "true") {
      fail("Custom refresh header not sent");
    }
  });

  test(
      "Test that network calls that dont require authentication work properly before, during and after login when using SuperTokensHttpClient",
      () async {
    await startST(validity: 10);

    try {
      SuperTokens.initialise(
        refreshTokenEndpoint: refreshTokenUrl,
        sessionExpiryStatusCode: sessionExpiryCode,
      );
    } catch (e) {
      fail("Error initialising super tokens");
    }

    int counterBefore = await getRefreshTokenCounterUsingST();

    if (counterBefore != 0) {
      fail("API call before failed");
    }

    http.Response loginResponse =
        await networkClient.post(Uri.parse(loginAPIURL));

    if (loginResponse.statusCode != 200) {
      fail("Login API failed");
    }

    int counterDuring = await getRefreshTokenCounterUsingST();

    if (counterDuring != 0) {
      fail("API call during failed");
    }

    http.Response logoutResponse =
        await networkClient.post(Uri.parse(logoutAPIURL));
    if (logoutResponse.statusCode != 200) {
      fail("Logout API failed");
    }

    if (await SuperTokens.doesSessionExist()) {
      fail("Session exixts according to supertokens when it shouldnt");
    }

    int counterAfter = await getRefreshTokenCounterUsingST();

    if (counterAfter != 0) {
      fail("API call after failed");
    }
  });

  test(
      "Test that network calls that dont require authentication work properly before, during and after login without using SuperTokensHttpClient",
      () async {
    await startST(validity: 10);

    try {
      SuperTokens.initialise(
        refreshTokenEndpoint: refreshTokenUrl,
        sessionExpiryStatusCode: sessionExpiryCode,
      );
    } catch (e) {
      fail("Error initialising super tokens");
    }

    int counterBefore = await SuperTokensTestUtils.getRefreshTokenCounter();

    if (counterBefore != 0) {
      fail("API call before failed");
    }

    http.Response loginResponse =
        await networkClient.post(Uri.parse(loginAPIURL));

    if (loginResponse.statusCode != 200) {
      fail("Login API failed");
    }

    int counterDuring = await SuperTokensTestUtils.getRefreshTokenCounter();

    if (counterDuring != 0) {
      fail("API call during failed");
    }

    http.Response logoutResponse =
        await networkClient.post(Uri.parse(logoutAPIURL));
    if (logoutResponse.statusCode != 200) {
      fail("Logout API failed");
    }

    if (await SuperTokens.doesSessionExist()) {
      fail("Session exixts according to supertokens when it shouldnt");
    }

    if ((await SharedPreferences.getInstance())
                .getString("supertokens-flutter-anti-csrf") !=
            null ||
        (await IdRefreshToken.getToken()) != null) {
      fail("Either IdRefreshToken or AntiCSRF token is not null");
    }

    int counterAfter = await SuperTokensTestUtils.getRefreshTokenCounter();

    if (counterAfter != 0) {
      fail("API call after failed");
    }
  });

  test(
      "Test that idRefreshToken in storage changes properly when the network response sends a new header value",
      () async {
    await startST(validity: 3);
    try {
      SuperTokens.initialise(
        refreshTokenEndpoint: refreshTokenUrl,
        sessionExpiryStatusCode: sessionExpiryCode,
      );
    } catch (e) {
      fail("Error initialising super tokens");
    }

    http.Response loginResponse =
        await networkClient.post(Uri.parse(loginAPIURL));

    if (loginResponse.statusCode != 200) {
      fail("Login API failed");
    }

    String? idRefreshTokenBefore = await IdRefreshToken.getToken();
    await Future.delayed(Duration(seconds: 5));

    http.Response userInfoResponse =
        await networkClient.get(Uri.parse(userInfoAPIURL));

    if (userInfoResponse.statusCode != 200) {
      fail("UserInfo API failed");
    }

    String? idRefreshTokenAfter = await IdRefreshToken.getToken();

    if (idRefreshTokenBefore == idRefreshTokenAfter) {
      fail("Id refresh token before and after are the same");
    }
  });

  test(
      "Test that the refresh endpoint is called after the access token expires",
      () async {
    await startST(validity: 3);
    try {
      SuperTokens.initialise(
        refreshTokenEndpoint: refreshTokenUrl,
        sessionExpiryStatusCode: sessionExpiryCode,
      );
    } catch (e) {
      fail("Error initialising super tokens");
    }

    http.Response loginResponse =
        await networkClient.post(Uri.parse(loginAPIURL));

    if (loginResponse.statusCode != 200) {
      fail("Login API failed");
    }

    await Future.delayed(Duration(seconds: 5));

    http.Response userInfoResponse =
        await networkClient.get(Uri.parse(userInfoAPIURL));

    if (userInfoResponse.statusCode != 200) {
      fail("UserInfo API failed");
    }

    int refreshCounter = await SuperTokensTestUtils.getRefreshTokenCounter();
    if (refreshCounter != 1) {
      fail("Refresh counter was $refreshCounter, expected 1");
    }
  });

  test(
      "Test that refresh endpoint gets called only once for multiple parallel tasks",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that doesSessionExist returns false after credentials are cleared by a network response",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that doesSessionExist returns true when valid credentials are present",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that in the case of API errors the error message is returned to the function using SuperTokensHttpClient",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that network requests to domains other than SuperTokens.apiDomain work fine before, during and after logout",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that custom request headers are sent correctly when using SuperTokensHttpClient",
      () {
    // TODO: Add test case
    expect(true, false);
  });

  test(
      "Test that passing an instance of a custom client works as expected when using SuperTokensHttpClient",
      () {
    // TODO: Add test case
    expect(true, false);
  });
}
