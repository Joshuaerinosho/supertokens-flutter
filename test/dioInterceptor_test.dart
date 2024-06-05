import 'package:dio/dio.dart';
import 'package:dio_http_formatter/dio_http_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supertokens_flutter/src/dio-interceptor-wrapper.dart';
import 'package:supertokens_flutter/src/supertokens.dart';
import 'package:supertokens_flutter/src/utilities.dart';
import 'package:supertokens_flutter/supertokens.dart';

import 'test-utils.dart';

void main() {
  String apiBasePath = SuperTokensTestUtils.baseUrl;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SuperTokensTestUtils.beforeAllTest();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SuperTokensTestUtils.beforeEachTest();
    SuperTokens.isInitCalled = false;
    await Future.delayed(Duration(seconds: 1), () {});
  });
  tearDownAll(() async => await SuperTokensTestUtils.afterAllTest());

  Dio setUpDio() {
    Dio dio = Dio(
      BaseOptions(
        baseUrl: apiBasePath,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(milliseconds: 500),
      ),
    );
    dio.interceptors.add(SuperTokensInterceptorWrapper(client: dio));
    return dio;
  }

  test("Test session expired without refresh call", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = setUpDio();
    var resp = await dio.get("/");
    if (resp.statusCode != 401)
      fail("API should have returned unAuthorised but didn't");
    int counter = await SuperTokensTestUtils.refreshTokenCounter();
    if (counter != 0) fail("Refresh counter returned non zero value");
  });

  test("Test custom headers for refresh API", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(
      apiDomain: apiBasePath,
      preAPIHook: (action, req) {
        if (action == APIAction.REFRESH_TOKEN)
          req.headers.addAll({"custom-header": "custom-value"});
        return req;
      },
    );
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200)
      fail("Login req failed");
    else {
      await Future.delayed(Duration(seconds: 10), () {});
      var userInfoResp = await dio.get("/");
      if (userInfoResp.statusCode != 200) {}
    }
    var refreshResponse = await dio.get("/refreshHeader");
    if (refreshResponse.statusCode != 200) fail("Refresh Request failed");
    var respJson = refreshResponse.data;
    if (respJson["value"] != "custom-value") fail("Header not sent");
  });

  test("Test to check if request can be made without Supertokens.init",
      () async {
    await SuperTokensTestUtils.startST(validity: 3);
    dynamic error;
    try {
      RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
      Dio dio = setUpDio();
      await dio.fetch(req);
      fail("Request should have failed but didnt");
    } on DioError catch (e) {
      error = e.error;
    }

    assert(error != null);
    assert(error.toString() ==
        "SuperTokens.init must be called before using Client");
  });

  test('More than one calls to init works', () async {
    await SuperTokensTestUtils.startST(validity: 5);
    try {
      SuperTokens.init(apiDomain: apiBasePath);
      SuperTokens.init(apiDomain: apiBasePath);
    } catch (e) {
      fail("Calling init more than once fails the test");
    }
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    try {
      SuperTokens.init(apiDomain: apiBasePath);
    } catch (e) {
      fail("Calling init more than once fails the test");
    }
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200)
      fail("UserInfo API returned ${userInfoResp.statusCode} ");
  });

  test("Test if refresh is called after access token expires", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    bool failed = false;
    SuperTokens.init(apiDomain: apiBasePath);
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    await Future.delayed(Duration(seconds: 5), () {});
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200) failed = true;

    int counter = await SuperTokensTestUtils.refreshTokenCounter();
    if (counter != 1) failed = true;

    assert(!failed);
  });

  // test('Refresh only get called once after multiple request (Concurrency)',
  //     () async {
  //   bool failed = false;
  //   await SuperTokensTestUtils.startST(validity: 10);
  //   List<bool> results = [];
  //   SuperTokens.init(apiDomain: apiBasePath);
  //   RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
  //   Dio dio = setUpDio();
  //   var resp = await dio.fetch(req);
  //   if (resp.statusCode != 200) fail("Login req failed");
  //   List<Future> reqs = [];
  //   for (int i = 0; i < 300; i++) {
  //     dio.get("").then((resp) {
  //       if (resp.statusCode == 200)
  //         results.add(true);
  //       else
  //         results.add(false);
  //     });
  //   }
  //   await Future.wait(reqs);
  //   int refreshCount = await SuperTokensTestUtils.refreshTokenCounter();
  //   if (refreshCount != 1 && !results.contains(false) && results.length == 300)
  //     fail("");
  // });

  test("Test does session exist after user is loggedIn", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    bool sessionExist = false;
    SuperTokens.init(apiDomain: apiBasePath);
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");
    sessionExist = await SuperTokens.doesSessionExist();
    // logout
    var logoutResp = await dio.post("/logout");
    if (logoutResp.statusCode != 200) fail("Logout req failed");
    sessionExist = await SuperTokens.doesSessionExist();
    assert(!sessionExist);
  });

  test("Test if not logged in  the  Auth API throws session expired", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = setUpDio();
    var resp = await dio.get("/");

    if (resp.statusCode != 401) {
      fail("API should have returned session expired (401) but didnt");
    }
  });

  // test("Test other other domains work without Authentication", () async {
  //   await SuperTokensTestUtils.startST(validity: 1);
  //   SuperTokens.init(apiDomain: apiBasePath);
  //   Dio dio = setUpDio();
  //   Uri fakeGetApi = Uri.parse("https://www.google.com");
  //   var resp = await http.get(fakeGetApi);
  //   if (resp.statusCode != 200)
  //     fail("Unable to make Get API Request to external URL");
  //   Request req = SuperTokensTestUtils.getLoginRequest();
  //   StreamedResponse streamedResp;
  //   streamedResp = await http.send(req);
  //   var loginResp = await Response.fromStream(streamedResp);
  //   if (loginResp.statusCode != 200) {
  //     fail("Login failed");
  //   }
  //   resp = await http.get(fakeGetApi);
  //   if (resp.statusCode != 200)
  //     fail("Unable to make Get API Request to external URL");
  //   // logout
  //   Uri logoutReq = Uri.parse("$apiBasePath/logout");
  //   var logoutResp = await http.post(logoutReq);
  //   if (logoutResp.statusCode != 200) fail("Logout req failed");
  //   resp = await http.get(fakeGetApi);
  //   if (resp.statusCode != 200)
  //     fail("Unable to make Get API Request to external URL");
  // });

  test("Test that getAccessToken works correctly", () async {
    await SuperTokensTestUtils.startST(validity: 5);
    SuperTokens.init(apiDomain: apiBasePath);
    String? accessToken = await SuperTokens.getAccessToken();

    if (accessToken != null) {
      fail("Access token should be null but isn't");
    }

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    accessToken = await SuperTokens.getAccessToken();

    if (accessToken == null) {
      fail("Access token is null when it should not be");
    }

    await SuperTokens.signOut();

    accessToken = await SuperTokens.getAccessToken();

    if (accessToken != null) {
      fail("Access token should be null but isn't");
    }
  });

  test("Test that different casing for autherization header works fine",
      () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    String? accessToken = await SuperTokens.getAccessToken();

    dio.options.headers['Authorization'] = "Bearer $accessToken";
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200) {
      fail("User Info API failed with `Authorization`");
    }

    dio.options.headers['Authorization'] = "";
    dio.options.headers['authorization'] = "Bearer $accessToken";
    var userInfoResp2 = await dio.get("");
    if (userInfoResp2.statusCode != 200) {
      fail("User info API failed with `authorization`");
    }
  });

  test("Test manually adding expired accesstoken works normally", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    String? accessToken = await SuperTokens.getAccessToken();

    if (accessToken == null) {
      fail("Access token is null when it should not be");
    }

    await Future.delayed(Duration(seconds: 5), () {});

    dio.options.headers['Authorization'] = "Bearer $accessToken";
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200) {
      fail("User Info API failed");
    }
    int count = await SuperTokensTestUtils.refreshTokenCounter();
    if (count != 1) {
      fail("refreshTokenCounter returned an invalid count");
    }
  });

  test("Test that accesstoken calls refresh correctly", () async {
    await SuperTokensTestUtils.startST(validity: 3);
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    String? accessToken = await SuperTokens.getAccessToken();

    if (accessToken == null) {
      fail("Access token is null when it should not be");
    }

    await Future.delayed(Duration(seconds: 5), () {});

    String? newAccessToken = await SuperTokens.getAccessToken();

    if (accessToken == null) {
      fail("Access token is nil when it shouldnt be");
    }

    int count = await SuperTokensTestUtils.refreshTokenCounter();
    if (count != 1) {
      fail("refreshTokenCounter returned invalid count");
    }

    if (accessToken == newAccessToken) {
      fail("Access token after refresh is same as old access token");
    }
  });

  test("Test that old access token after signOut works fine", () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    String? accessToken = await SuperTokens.getAccessToken();

    if (accessToken == null) {
      fail("Access token is null when it should not be");
    }

    await SuperTokens.signOut();

    dio.options.headers['Authorization'] = "Bearer $accessToken";
    var userInfoResp = await dio.get("/");
    if (userInfoResp.statusCode != 200) {
      fail("User Info API failed");
    }
  });

  test("Test that access token and refresh token are cleared after front token is removed", () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    String? accessToken = await Utils.getTokenForHeaderAuth(TokenType.ACCESS);
    String? refreshToken = await Utils.getTokenForHeaderAuth(TokenType.REFRESH);

    assert(accessToken != null);
    assert(refreshToken != null);

    RequestOptions req2 = SuperTokensTestUtils.getLogoutAltRequestDio();
    await dio.fetch(req2);

    String? accessTokenAfter = await Utils.getTokenForHeaderAuth(TokenType.ACCESS);
    String? refreshTokenAfter = await Utils.getTokenForHeaderAuth(TokenType.REFRESH);

    assert(accessTokenAfter == null);
    assert(refreshTokenAfter == null);
  });

  test("Test other other domains work without Authentication", () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    String url = 'https://www.google.com/';
    Dio dio = setUpDio();
    var respGoogle1 = await dio.get(url);
    if (respGoogle1.statusCode! > 300) fail("external API did not work");
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio2 = setUpDio();
    var loginResp = await dio2.fetch(req);
    if (loginResp.statusCode != 200) fail("Login req failed");
    var respGoogle2 = await dio.get(url);
    if (respGoogle2.statusCode! > 300) fail("external API did not work");
    // logout
    var logoutResp = await dio2.post("/logout");
    if (logoutResp.statusCode != 200) fail("Logout req failed");
    var respGoogle3 = await dio.get(url);
    if (respGoogle3.statusCode! > 300) fail("external API did not work");
  });

  test('Testing multiple interceptors -- After SuperTokensInterceptorWrapper',
      () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = Dio(
      BaseOptions(
        baseUrl: apiBasePath,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(milliseconds: 500),
      ),
    );
    dio.interceptors.add(SuperTokensInterceptorWrapper(client: dio));
    dio.interceptors.add(HttpFormatter());
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    var loginResp = await dio.fetch(req);
    if (loginResp.statusCode != 200) fail("Login req failed");
  });

  test('Testing multiple interceptors -- Before SuperTokensInterceptorWrapper',
      () async {
    await SuperTokensTestUtils.startST(validity: 1);
    SuperTokens.init(apiDomain: apiBasePath);
    Dio dio = Dio(
      BaseOptions(
        baseUrl: apiBasePath,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(milliseconds: 500),
      ),
    );
    dio.interceptors.add(HttpFormatter());
    dio.interceptors.add(SuperTokensInterceptorWrapper(client: dio));
    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    var loginResp = await dio.fetch(req);
    if (loginResp.statusCode != 200) fail("Login req failed");
  });

  test("should not ignore the auth header even if it matches the stored access token", () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    if (resp.statusCode != 200) fail("Login req failed");

    await Future.delayed(Duration(seconds: 5), () {});

    Utils.setToken(TokenType.ACCESS, "myOwnHeHe");

    dio.options.headers['Authorization'] = "Bearer myOwnHeHe";
    var userInfoResp = await dio.get("/base-custom-auth");
    if (userInfoResp.statusCode != 200) {
      fail("User Info API failed");
    }
  });

  test(
      "should break out of session refresh loop after default maxRetryAttemptsForSessionRefresh value",
      () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(
        apiDomain: apiBasePath);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    assert(resp.statusCode == 200, "Login req failed");

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 0,
        "refresh token count should have been 0");

    try {
      await dio.get("/throw-401");
      fail("Expected the request to throw an error");
    } on DioException catch (err) {
      assert(err.error.toString() ==
          "Received a 401 response from http://localhost:8080/throw-401. Attempted to refresh the session and retry the request with the updated session tokens 10 times, but each attempt resulted in a 401 error. The maximum session refresh limit has been reached. Please investigate your API. To increase the session refresh attempts, update maxRetryAttemptsForSessionRefresh in the config.");
    }

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 10,
        "session refresh endpoint should have been called 10 times");
  });

  test(
      "should break out of session refresh loop after configured maxRetryAttemptsForSessionRefresh value",
      () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(
        apiDomain: apiBasePath, maxRetryAttemptsForSessionRefresh: 5);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    assert(resp.statusCode == 200, "Login req failed");

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 0,
        "refresh token count should have been 0");

    try {
      await dio.get("/throw-401");
      fail("Expected the request to throw an error");
    } on DioException catch (err) {
      assert(err.error.toString() ==
          "Received a 401 response from http://localhost:8080/throw-401. Attempted to refresh the session and retry the request with the updated session tokens 5 times, but each attempt resulted in a 401 error. The maximum session refresh limit has been reached. Please investigate your API. To increase the session refresh attempts, update maxRetryAttemptsForSessionRefresh in the config.");
    }

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 5,
        "session refresh endpoint should have been called 5 times");
  });

  test(
      "should not do session refresh if maxRetryAttemptsForSessionRefresh is 0",
      () async {
    await SuperTokensTestUtils.startST();
    SuperTokens.init(
        apiDomain: apiBasePath, maxRetryAttemptsForSessionRefresh: 0);

    RequestOptions req = SuperTokensTestUtils.getLoginRequestDio();
    Dio dio = setUpDio();
    var resp = await dio.fetch(req);
    assert(resp.statusCode == 200, "Login req failed");

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 0,
        "refresh token count should have been 0");

    try {
      await dio.get("/throw-401");
      fail("Expected the request to throw an error");
    } on DioException catch (err) {
      assert(err.error.toString() ==
          "Received a 401 response from http://localhost:8080/throw-401. Attempted to refresh the session and retry the request with the updated session tokens 0 times, but each attempt resulted in a 401 error. The maximum session refresh limit has been reached. Please investigate your API. To increase the session refresh attempts, update maxRetryAttemptsForSessionRefresh in the config.");
    }

    assert(await SuperTokensTestUtils.refreshTokenCounter() == 0,
        "session refresh endpoint should have been called 0 times");
  });
}
