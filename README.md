# Prime OS - A Simple Unix Like System for CC: Tweaked
\- Unix Like System on CC:Tweaked and Lua. \-

Copyright (c) 2024 akki697222 \- MIT License
# TODO
- プロセス管理について学び、カーネルに実装する <- スケジューリングあたりがまだ
- [これ](https://0xax.gitbooks.io/linux-insides/content/index.html)を見てもっとlinuxについて知る(https://keichi.dev/post/linux-boot/ より)
- ~~カーネル初期段階の描画用ターミナルを作成し、さらにそれからvtへの移行プロセスを作成する~~
- ttyを実装する <- WIP
- vtを実装する <- WIP
  - CCVTという独自のvtを作成する
  - 先にVT100
- ptyを実装する
- tty、pty、vtの３種がほぼ完成したらネットワーキングを作ってみる
- initの実装について調べ、よさそうなのを実装する <- systemdライク
- ~~ユーザーモジュールと権限のシステムを作成する~~

(終わったやつは~~このように~~線を引いておく)