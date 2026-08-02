# Spring Boot / FastAPI / Gin 徹底比較

調査日: 2026-08-02。対象は Spring Boot 4.1.0、FastAPI 公式ドキュメント、
Gin 1.12.0 世代の公式ドキュメントである。性能値は設計判断に使わず、公式に
公開された測定の読み方だけを扱う。kofun-boot 自身の数値は L5 の同一マシン
gate が測定するまで未測定のままとする。

## 結論

3者は「HTTPリクエストを関数へ渡す」という同じ仕事をするが、強みの源泉は
違う。

- **Spring Boot** はアプリケーション全体の起動・設定・運用・テストを一つの
  製品体験にまとめる。kofun-boot が最も強く採用すべきなのは router API では
  なく、starter、条件付き構成、Actuator、test slice、Initializr が作る
  「最初の1時間から運用まで」の連続性である。
- **FastAPI** は Python の型注釈と path operation 宣言から検証、OpenAPI、
  対話的ドキュメントを同時に得る。kofun-boot が採用するのは
  「宣言を文書へ投影する」性質であり、実行時の decorator/DI graph ではない。
- **Gin** は小さな handler-first core、明示的な `Context`、Go標準の
  `httptest`、低割り当て router を提供する。kofun-boot が採用するのは
  小さい serving substrate と測定規律であり、手書き route と onion middleware
  ではない。

従って kofun-boot の合成は **Spring Boot の製品面、FastAPI の一宣言性、Gin の
小さい実行面**である。ただし三つの実装を混ぜるのではない。一つの endpoint
値を build 時に dispatch、validation、OpenAPI、client へ投影し、shell が明示的な
capability record を一度だけ組み立てる。

## 比較軸

| 軸 | Spring Boot 4.1 | FastAPI | Gin | kofun-boot の判断 |
|---|---|---|---|---|
| 真実の置き場所 | annotation と bean/configuration | decorator、型注釈、Pydantic model | router 登録と handler 本体 | endpoint **値**を唯一の真実にする |
| 起動構成 | classpath と条件から auto-configuration | import した app と dependency graph | `gin.New` と明示的登録 | build 時投影、起動時は解決済みrecordを印字 |
| 依存関係 | IoC container の bean graph | `Depends` の graph | closure / struct / `Context` | capability を引数として渡す。containerなし |
| 入力検証 | Bean Validation 等とWeb stack | 型注釈・Pydanticから自動 | binding tagをhandlerで呼ぶ | endpoint contract の validation sum |
| API文書 | Spring ecosystemの投影を追加 | OpenAPI/JSON Schemaを自動生成 | coreには同一宣言の文書投影なし | dispatcherが読んだ表から必ず生成 |
| client | OpenAPI等の別工程 | OpenAPIから多言語生成可能 | 通常は別定義 |同じ表から生成しcompile gateを置く |
| 横断処理 | filter/interceptor/aspect/decorator | dependency/middleware | `c.Next()` のonion | shell の名前付き関数合成、順序を一箇所に固定 |
| テスト | full context とfocused test modules/slices | HTTPX系 `TestClient` とpytest | `httptest.ResponseRecorder` と標準testing | core直呼び + real socket integration |
| 運用面 | Actuator、外部設定、production defaults | ASGI ecosystemとの組合せ | `net/http` ecosystemとの組合せ | limits、drain、health、effective configを一級契約にする |
| 性能主張 | workload依存 | workload依存 | 公式router benchmarkに環境を明記 | 同じbox・同じhandler以外はbarにしない |

## Spring Boot 4.1 — 採るのは container ではなく「Boot」

公式 reference は auto-configuration を、追加された jar dependency に基づいて
構成を試みる仕組みと説明し、ユーザーが独自 bean を定義すると該当する既定構成が
後退すると明記する。これは単なる省略記法ではない。**既定を提供しながら、局所的に
置き換えられる**ことが Spring Boot の中心的な設計である。

また公式 testing reference は、core test module、auto-configuration test module、
機能別 test module を分ける。全container起動だけをテスト手段にせず、構成の一部を
検証する製品面まで含めている点が重要である。

kofun-boot では classpath scanning や application context を再現しない。Kofun は
ambient authority を持たず、dependency は値として渡せるため、container が解く
問題の多くが存在しない。その代わり次を採用する。

1. `boot new` が初回から core/shell/module gate を通るfixtureを出す。
2. starter相当は import bundle ではなく、明示的な capability record builder とする。
3. auto-configuration report 相当として、解決済み設定・採用したadapter・拒否した
   capabilityを起動時に安定した順序で印字する。
4. Actuator相当の health/readiness/metrics は、routeの横に手書きせず、runtime
   contract の投影とする。
5. test slice相当は module core、module shell、real socket、replay trace の4段階に
   固定する。

## FastAPI — 型から文書までの距離をゼロにする

FastAPI 公式 features は OpenAPI と JSON Schema を基礎にし、path operation、
parameters、request body、security の宣言から自動文書を作ると説明する。
dependency と sub-dependency のrequest宣言・validationも同じ OpenAPI schema に
統合される。公式 testing guide は Starlette/HTTPX由来の `TestClient` を通じて
pytestからappを直接テストする。

ここから採るべき性質は二つである。

- endpointを追加した瞬間に検証と文書も増える。文書更新は別タスクではない。
- HTTPサーバーを起動しない高速テストと、実際のsocketを通るintegration testを
  分ける。

一方、kofun-boot は decorator metadata と実行時 dependency graph を真実には
しない。`contracts/boot.kofun` の endpoint 値をbuild時に全投影し、投影が一件でも
欠ければ route count gate が失敗する。dependencyがrequest validationを追加する
場合も、隠れた graph edge ではなく endpoint 値のinput contractとして現れる。

## Gin — 小さいcoreと測定方法を採り、onionを採らない

Gin 公式 middleware guide は `gin.HandlerFunc` が `c.Next()` を呼ぶ onion model を
明示する。global、group、route の三箇所へmiddlewareを取り付けられ、広いscopeが
先に実行される。柔軟だが、最終的な順序は複数箇所の登録を読まなければ分からない。

公式 testing guide は `httptest.NewRecorder` と最小routerでhandlerやmiddlewareを
検証する。公式 benchmark は version、Go version、OS/architecture、日付、workloadを
併記する。数値そのものではなく、**測定値に provenance を付ける**規律を採用する。

kofun-boot では次のように適応する。

- Gin の小さいhandler substrateに相当する部分は `framework/http` に任せる。
- binding tagをhandler内で呼ぶ代わりに、validationをendpoint tableから生成する。
- `Context` の汎用bagへdependencyを入れず、handlerの引数で必要capabilityを示す。
- middlewareはshellに一つの名前付きcompositionとして並べ、実行順を印字する。
- benchmarkはrouter microbenchmarkとend-to-endを分離し、同じhandler・同じbox・
  machine provenance付きで保存する。

## 採用・適応・不採用

| 判定 | 項目 | 理由 |
|---|---|---|
| adopt | Spring Bootのone-command scaffoldと運用surface | frameworkはrouter以上の製品である |
| adopt | FastAPIの宣言→validation/OpenAPI | driftを工程ではなく構造で不可能にする |
| adopt | Ginの小さいserving coreとbenchmark provenance | runtimeを小さくし、主張を再現可能にする |
| adapt | DI | containerではなく、scope付きcapability recordとfake recordにする |
| adapt | middleware | onionではなくshellの明示的関数合成にする |
| adapt | test slice | framework固有annotationではなくcore/shell/socket/replayのgateにする |
| reject | handler-firstの手書きOpenAPI/client | routeと成果物が独立に変化できる |
| reject | 実行時scanを契約の真実にすること | build時にtotalityと重複を拒否できない |
| reject | 出典の異なるreq/sを横並びにすること | handler、runtime、boxが違い設計barにならない |

## 実装へ落ちる項目

- L1: endpoint tableからdispatch、validation、OpenAPI、typed clientを生成する。
- L2/L3: effective configとcapability manifestを一つの起動recordとして印字する。
- L5: Gin公式benchmarkが示すprovenance項目を最小要件にし、同一box比較を行う。
- L8: `boot new`、`boot dev`、`boot test`を同じgateの入口にする。
- L10: この文書を含むresearch packを決定的ZIPとして生成する。

## 一次資料

- [Spring Boot 4.1 Auto-configuration](https://docs.spring.io/spring-boot/reference/using/auto-configuration.html)
- [Spring Boot 4.1 Testing](https://docs.spring.io/spring-boot/reference/testing/index.html)
- [FastAPI Features](https://fastapi.tiangolo.com/features/)
- [FastAPI Dependencies](https://fastapi.tiangolo.com/tutorial/dependencies/)
- [FastAPI Testing](https://fastapi.tiangolo.com/tutorial/testing/)
- [Gin Middleware](https://gin-gonic.com/en/docs/middleware/)
- [Gin Testing](https://gin-gonic.com/en/docs/testing/)
- [Gin Benchmarks](https://gin-gonic.com/en/docs/benchmarks/)
