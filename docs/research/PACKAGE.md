# kofun-boot framework research pack

スナップショット日: 2026-08-02

このZIPは、Spring Boot / FastAPI / Ginを中心とするWeb framework比較、
modular-monolith-with-dddのDDD戦術パターン分析、desktop/effect/renderingの調査、
およびそこから採用したkofun-bootのarchitecture decisionを一つにまとめた成果物で
ある。

## 最短の読み順

1. `docs/research/SPRING_FASTAPI_GIN.md`
2. `docs/research/MODULAR_MONOLITH_DDD.md`
3. `docs/architecture/FDDD.md`
4. `docs/architecture/EFFECTS.md`
5. `docs/architecture/TEA.md`
6. `docs/ROADMAP.md`

`docs/research/WEB_FRAMEWORKS.md` は対象を広げた比較、`DESKTOP_FRAMEWORKS.md` と
`RENDER_BACKENDS.md` はdesktop lane、`EFFECT_SYSTEMS.md` はeffect modelの根拠を
扱う。

## 検証

ZIP直下の `MANIFEST.sha256` は、manifest自身を除く全収録fileのSHA-256を持つ。

```sh
unzip kofun-boot-framework-research-2026-08-02.zip
cd kofun-boot-framework-research-2026-08-02
sha256sum -c MANIFEST.sha256
```

repositoryから同じ成果物を再生成する場合:

```sh
sh scripts/build-research-pack.sh dist
sh tests/research/check.sh
```

生成scriptは収録順、timestamp、ZIP extra fieldを固定する。gateは通常環境と
`env -i`の二回で生成し、ZIPとdigestがbyte-identicalであることを確認する。

## 境界

- 外部repositoryのsource codeやWeb page本文は再配布しない。収録するのは出典URL、
  commit pin、要約、設計判断である。
- 外部benchmarkの数値はkofun-bootの性能値ではない。kofun-bootの比較値は同じbox、
  同じhandlerをL5 gateで測るまで未測定である。
- moduleの縦割りownership、contract-only dependency gate、closed business outcome
  seedは実装済みである。Outbox/Inbox、module別database schema、event sourcingは
  引き続き調査・設計段階であり、全てが実装済みという意味ではない。各文書の
  adopt/adapt/deferを参照する。

## License

このpack内のkofun-boot文書はrepositoryと同じ Apache-2.0 OR MIT。リンク先の資料・
projectにはそれぞれのlicenseと利用条件が適用される。
