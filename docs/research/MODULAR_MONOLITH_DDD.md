# modular-monolith-with-ddd から何を採用するか

調査日: 2026-08-02。原典は
[`kgrzybek/modular-monolith-with-ddd`](https://github.com/kgrzybek/modular-monolith-with-ddd)
の commit
[`91c8ef24b4cb6ef558c95d8267fa07d68c7059f8`](https://github.com/kgrzybek/modular-monolith-with-ddd/tree/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8)
に固定した。以下の「現状」はこのcommitについての記述であり、一般的なDDDの唯一の
実装方法という主張ではない。

## 結論

このreferenceから採用する中心は、class名や.NET libraryではない。

1. **moduleはbounded contextの縦の所有境界**であり、domainだけでなくcontract、
   application/core、infrastructure/shell、testsを同じmoduleが所有する。
2. **他moduleが参照できるのは公開contractだけ**であり、coreやshellへ直接入らない。
3. **business ruleは名前のある値**として表す。ただし `bool + string + exception` は
   closed sumへ変換し、拒否理由が観測値を保持するようにする。
4. **module間整合性はlocal transactionだと偽らない**。integration event、outbox、
   inbox、idempotency、replayを一つの設計として扱う。
5. **architecture ruleは機械的に検査する**。ただしtest名とassertionを二重管理せず、
   実際の違反pathと行を一つのgateが報告する。

CQRS、event sourcing、repository、decorator、module別schemaは一括採用しない。
それぞれが解く問題と、Kofunの現行compiler/runtimeで実証できる範囲を分離する。

## 原典の構造

原典のREADMEは、一つのprocess内に User Access、Registrations、Meetings、
Administration、Payments を置き、APIを薄いhostとする。moduleは次を所有する。

| 原典のsubmodule | 責務 | Kofunへの写像 |
|---|---|---|
| Domain | aggregate、entity、value object、domain event、business rule | `core/` のdomain型とpure transition |
| Application | command/query handler、use case、internal command | `core/` のderiver/updateと公開use-case contract |
| Infrastructure | adapter、composition root、background processing、data access | `shell/` のcapability interpreterとadapter |
| IntegrationEvents | 他moduleが参照できるevent contract | `contract/` のversioned public event sum |
| Tests | domain、application、architecture、integration | module直下の `tests/`、global gateは集約だけ行う |

原典はmodule間の直接method callを禁じ、IntegrationEvents assemblyだけを参照可能に
する。またmoduleごとにdatabase schemaを分け、module間イベントへOutbox/Inboxを
使う。これは「後でmicroserviceに分けられる」こと自体より、**所有権とtransaction
境界を一致させる**ことに価値がある。

## DDD戦術パターンの採否

| パターン | 判定 | kofun-bootでの形 |
|---|---|---|
| Bounded Context | adopt | module directoryと公開contractの境界を一致させる |
| Entity | adapt | identityを持つrecord。状態変更はin-place mutationでなく新しい値を返す |
| Value Object | adopt | nominal record + smart constructor + closed validation sum |
| Aggregate | adapt | local invariantの整合境界。純粋なtransitionが新stateとdomain eventsを返す |
| Business Rule | adapt | `IsBroken(): bool` でなく、観測値を運ぶclosed outcome sum |
| Domain Event | adopt | 過去形のimmutable value。module内部eventと公開integration eventを分ける |
| Domain Service | adapt | entityへ不自然に押し込めないpure deriver。capabilityを持たない |
| Repository | adapt | domain interfaceをcontainer解決せず、shellが渡すcapability function |
| Application Service / Handler | adapt | fetch → pure transition → `Cmd`解釈。domain ruleを再実装しない |
| Unit of Work | defer | data laneがlocal transaction contractを持つ時だけ導入 |
| CQRS | conditional | read/write modelが本当に異なる時だけ。全use caseの既定形にしない |
| Outbox / Inbox | adopt direction | deliveryはat-least-once、consumerはidempotent、trace replayをgateにする |
| Event Sourcing | reject as default | audit/replayとaggregate復元を混同せず、必要なmoduleだけが採用する |

## business rule — 値は採用し、exceptionは採用しない

原典の
[`IBusinessRule.cs`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/BuildingBlocks/Domain/IBusinessRule.cs)
は `IsBroken(): bool` と `Message` を持つ。ruleを名前のあるobjectへ分離するため、
単なるif文よりレビュー・単体テスト・用語統一に強い。一方、
[`Entity.CheckRule`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/BuildingBlocks/Domain/Entity.cs)
は破られたruleをexceptionに変える。

kofun-bootでは半分だけ採る。ruleはpure value/functionだが、結果は例えば次のclosed
sumにする。

```text
MeetingDecision =
    MeetingCreated(change)
  | GroupPaymentExpired(expired_at, observed_at)
  | HostIsNotMember(host_id, group_id)
```

拒否は例外ではなくdomainの正しい回答であり、各constructorは「なぜ」を再計算せず
表示・記録できる観測値を持つ。I/O failureだけを `Result.Err` とする。

## Aggregateとevent — mutable object graphをpure transitionへ変える

原典はaggregateのpublic methodへruleを集中し、domain eventを内部listへ追加する。
これはinvariantの置き場所として正しい。ただしkofun-bootでは状態と未送信eventを
hidden mutable listに置かない。

```text
decide : Aggregate -> Command -> Decision
evolve : Aggregate -> DomainEvent -> Aggregate
Decision = Rejected(DomainOutcome) | Accepted(new_state, events)
```

この形なら、同じstateとcommandは同じdecisionを返す。record/replayする対象が明確で、
testはprivate fieldを開けずにpublic transitionだけを検証できる。

## CQRS — handler数ではなくmodel差で判断する

原典はcommandをDDD write model、queryをraw SQL read modelで処理し、decoratorで
logging、validation、unit of workを合成する。read/writeの形と負荷が違うsystemでは
有効である。しかし「command/queryを別classにした」だけではCQRSの運用コストを
正当化しない。

kofun-bootの既定は一つのendpoint contractとpure use-caseである。次の条件が計測・
仕様で示されたmoduleだけread projectionを分離する。

- read shapeがaggregate shapeと継続的に異なる。
- eventual consistencyを利用者へ説明できる。
- projection rebuildとlagを観測・replayできる。
- command側のlocal invariantをread modelへ漏らさない。

## module間通信 — contractだけを名前にできる

採用するdependency ruleは単純である。

```text
modules/<a>/core      -> 自moduleのcontract/coreだけ
modules/<a>/shell     -> 自moduleのcontract/core/shell + platform capability
modules/<a>/tests     -> 自module全体
modules/<a>           -> modules/<b>/contract だけ参照可能
host                  -> 各moduleのcontract/shell composition entryだけ
```

公開contractはdomain objectそのものを共有しない。BillingのCustomerとSupportの
Customerは別の意味を持ち得る。他moduleへ出す値はversioned integration eventか
query contractであり、受信moduleが自分の語彙へ変換する。

「module間は常にasync」も絶対規則にはしない。状態変更eventはasync + outboxを基本に
するが、同じprocess内のpure、失敗しない、所有権を侵さないlookupまでeventual
consistencyへ強制するかはuse caseで決める。重要なのは同期/非同期の好みではなく、
他moduleのcore/shellを直接参照できないことである。

## Outbox / Inbox — transactionよりreplayを中心に置く

原典はmoduleごとのOutbox/Inboxとbackground workerにより、at-least-once deliveryと
at-least-once processingを扱う。kofun-bootではこれをL7 dataだけの補助機能にせず、
L4 replayと接続する。

1. local state changeとoutbox appendは同じmodule transactionに入れる。
2. event id、contract version、producer module、causation idを記録する。
3. consumerはinboxでevent idをdeduplicateする。
4. retry/backoff/timeoutはambient clockでなくcapability answerとしてtraceへ入れる。
5. replayは最初に異なるstep、expected command、observed commandを報告する。

data contractがまだ実行可能でない間は、これを「実装済み」と書かない。contractと
trace seedを先にgateし、database adapterはL7のlanguage blocker解消後に置く。

## architecture gate — 原典の失敗から学ぶ

原典の
[`Meetings/LayersTests.cs`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/Modules/Meetings/Tests/ArchTests/Module/LayersTests.cs)
では `DomainLayer_DoesNotHaveDependency_ToInfrastructureLayer` というtest名に対し、
assertionは `ApplicationAssembly` を参照する。Domain→Infrastructure ruleはそのtestで
検査されない。

問題は個人の注意力ではなく、rule名とassertionが別の文字列として増殖する構造で
ある。kofun-bootはADR 2の通り、一つのgateがsourceを読み、違反module、参照先、path、
lineをそのまま報告する。gate追加時は必ず一度違反を注入し、期待する名前で失敗する
ことも確認する。

## 採用したmodule layout

Issue #36 で次のlayoutを採用した。`router` と `mock` はこの形へ実際に移動し、
data-driven gateを通る。調査上の推奨に留めず、既存codeが収まることまで確認した。

```text
modules/
  router/
    contract/
    core/
    shell/
    tests/
  mock/
    contract/
    core/
    shell/
    tests/
host/
tests/
  architecture/
  integration/
```

module内の小規模な実装をさらにDomain/Application/Infrastructureというdirectoryへ
分けることは要求しない。縦の所有権とcore/shell ruleが守られている限り、水平layer
を増やすほどnavigation costが上がるためである。

実装evidenceは次の通りである。

- `scripts/check-modules.sh` はmodule名をhard-codeせず、全moduleの4 directoryを検査する。
- `tests/architecture/check.sh` は第三の `orders` moduleを追加し、既存moduleを編集せず
  PASSすることを確認する。
- 同testは `../../router/core/router` を注入し、違反source、line、許可される
  `../../router/contract` をdiagnosticが示すことを確認する。
- `modules/mock/contract/mock.kofun` と実行可能seedの `MockOutcome` blockはbyte単位で
  比較され、全constructorが観測値を保持する。

## 採用・適応・不採用

| 判定 | 原典からの項目 | kofun-bootでの結果 |
|---|---|---|
| adopt | moduleがcontract/core/shell/testsを所有 | directoryとgateで強制 |
| adopt | module間は公開integration contractだけ | 他module core/shell参照をgateで拒否 |
| adopt | ruleを名前のある値にする | closed outcome sumとして観測値を保持 |
| adopt | Outbox/Inboxのat-least-once前提 | idempotencyとreplay traceを同時に要求 |
| adapt | aggregate + domain events | pure `decide/evolve`、新stateとeventsを返す |
| adapt | repository/UoW/decorator | capability function、Cmd interpreter、明示的shell composition |
| conditional | CQRS/read model | model差とeventual consistencyの根拠があるmoduleのみ |
| reject | business ruleをexceptionへ変換 | domain rejectionはanswerでありsystem failureではない |
| reject | event sourcingを標準templateにする |必要性、migration、projection運用がmoduleごとに異なる |
| reject | test名ごとにarchitecture assertionを複製 | 一つのdata-driven gateが違反sourceを報告 |

## 一次資料

- [README: architecture, CQRS, modules integration, tests, event sourcing](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/README.md)
- [`IBusinessRule`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/BuildingBlocks/Domain/IBusinessRule.cs)
- [`Entity` and rule checking](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/BuildingBlocks/Domain/Entity.cs)
- [`UnitOfWorkCommandHandlerDecorator`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/Modules/Meetings/Infrastructure/Configuration/Processing/UnitOfWorkCommandHandlerDecorator.cs)
- [`MeetingGroupProposedIntegrationEvent`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/Modules/Meetings/IntegrationEvents/MeetingGroupProposedIntegrationEvent.cs)
- [`LayersTests`](https://github.com/kgrzybek/modular-monolith-with-ddd/blob/91c8ef24b4cb6ef558c95d8267fa07d68c7059f8/src/Modules/Meetings/Tests/ArchTests/Module/LayersTests.cs)
