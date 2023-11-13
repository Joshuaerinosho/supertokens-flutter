import 'package:dio/dio.dart';
import 'package:dio_http_formatter/dio_http_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supertokens_flutter/src/supertokens.dart';
import 'package:supertokens_flutter/src/utilities.dart';
import 'package:supertokens_flutter/supertokens.dart';
import 'package:supertokens_flutter/dio.dart';

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

  tearDownAll(() => SuperTokensTestUtils.afterAllTest());

  Dio setUpDio() {

    final dio = Dio(
      BaseOptions(
        baseUrl: apiBasePath,
        connectTimeout: Duration(seconds: 5),
        receiveTimeout: Duration(milliseconds: 500),
      ),
    )
      ..addSupertokensInterceptor(); // Set up dio with cascade operator

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
    } on DioException catch (e) {
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

  test("Test manually adding expired access token works normally", () async {
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

    if (newAccessToken == null) {
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
}
