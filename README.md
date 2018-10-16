### CONBU IX2105 向けでっちあげスクリプト

初期化して再起動した状態のIX2105をシリアルコンソールに接続してこのスクリプトを動かすと、よしなにセットアップしてくれる子。
CONBUで使っているVPN構成を、シリアルコンソールのみで自己完結的に設定を仕込みます。

```
書式
sudo ruby ./conbu-ix2105-detchup.rb -c [コンフィグ] -t [テンプレート] -i [ターゲットの名前] -C [コンソールデバイス]

例
sudo ruby ./conbu-ix2105-detchup.rb -c sample.config.json -t ix2105-template.txt -i IX00X -C /dev/tty.usbserialXXXX
```

このスクリプトの実行には cu が必要です。他のターミナルの screen や cu は全部落とした状態で実行してください。
エラーチェックはないため、目でgrepしておかしなところは見つけてください。

標準で付属するテンプレート(ix2105-template.txt)では以下のようになっています。

- 対応しているのは IX2105 のみです
  - GE0とGE1があれば適用できるため他のIXシリーズでも使えそうな気はしますが試してはいません。
- 上流回線として DHCP あるいは PPPoE を選択可能です。
  - pppoeアカウント ("pppoe-id"と"pppoe-password")が設定されていればPPPoEを使います
  - それ以外の場合はDHCPを利用します
  - このいずれかの回線を使って、IPsec peerへ疎通があるものと認識します
- IKEアグレッシヴモードでVPNを確立します
  - フェーズ1は暗号化 AES 256bit、ハッシュアルゴリズム SHA2-512、DHグループ 2048bit としています
    - レスポンダ(対向側)と相互でマッチするように変更が必要になることがあります
  - フェーズ2の通信自体の暗号化にESP-AES-256, ESP-SHA2-512を用います
  - local-idとして自分が抱えてる ipsec-local-net 、reomte-idとして0.0.0.0/0 つまりインターネットとのポリシを提示しあいます
- LAN側は2インタフェースに分かれています: MGMTとUSER
  - MANAGEMENTはネットワーク機器類が用いるネットワークです、VLAN3000
  - USER は来場者の端末たちが用いるネットワークです、VLan3001
- ゲートウェイでは様々なネットワークサービスを有効にしています。
  - DHCPリレー
    - 各インタフェースか共通DHCPサーバに飛ばします
- ゲートウェイでは管理用の様々な機能を有効にしています
  - ntp
  - syslog
  - ssh-server
  - ntp
  - snmp-agent

類似品としてIX2025を対象にした[conbu/conbu-ix2025-detchup](https://github.com/conbu/conbu-ix2025-detchup)があります。
テンプレートを極度に抽象化すると読みづらいため、IX2025とは独立させています。

### 使い方

##### 0.機器のシリアルコンソールを握る

ここでは screen あるいは cu を想定しています

```
自分のPCで以下を実行しコンソールをつかんでください
% sudo screen /dev/tty.usbserialXXX 9600
または
% sudo cu -l /dev/tty.usbserialXXX -s 9600
```

##### 1.ターゲットのIX2105を初期化する

パスワードがわかっている場合は以下の通り設定をすべて吹き飛ばしましょう。

```
こちらで設定全削除
# erase startup-config
こちらで再起動
# reload
```

あるいは最初からスーパーリセットによる初期化を行う場合は取り扱い説明書の「スーパーリセット」(6-35)の手順に従って初期化しましょう

  - [UNIVERGE IXシリーズ マニュアル](https://jpn.nec.com/univerge/ix/Manual/index.html#um)

##### 2.sreen/cuを終了する

以下のプロンプトが出ている状態でscreenあるいはcuを落とします
```
Router#

screenなら"^a+k"
cuなら"~~"
```
落として手放したら放置

##### 3.conbu-ix2105-detchupを実行する

放置されているコンソールを conbu-ix2105-detchup で設定します。

```
たとえばIX101をターゲットに実行する場合

% sudo ruby ./conbu-ix2105-detchup.rb -c config.json -t ix2105-template.txt -i IX101 -C /dev/tty.usbserialXXX
```

途中で設定されるコンフィグが表示されるので確認してENTER、やめる場合はctrl + c


##### 4.再度シリアルコンソールを握り、コンフィグ確認 & write memory

write memoryまでは行わないため、再度screenなどで入りコンフィグをチェックした上でwrite memoryないしcopy run startしてください。


### コンフィグのパラメータ

コンフィグ(config.json)は以下のような構造のJSONファイルです。

```
{
	"common": {        # 複数機器間で共通のパラメータを書く場所
		"user": "testuser",
		...
	},

	"IX101": {         # ルータごとに固有のパラメータを書く場所
		"port":
	},
	...                # 各ルータの設定が並ぶ
}
```

テンプレート内では共通パラメータを common 、個別パラメータを my として参照可能です。
コマンドのiオプションで指定したルータ名と上記"IX101"といった文字列が照合され、マッチする名前のコンフィグ内のエントリが my に格納されます。

基本的にはハッシュに書いた内容がそのまま渡されます。
ただし、以下のパラメータがテンプレートエンジンにより自動的に生成されます。

- "hostname": iオプションで指定したターゲットの名前をそのまま利用
- "mgmt-addr-host": mgmt-prefixからホストのアドレスを生成したもの(プレフィクスを除去)
- "user-addr-host": user-prefixからホストのアドレスを生成したもの(プレフィクスを除去)

### テンプレート(ix2105-template.txt)について

CONBUで用いている会場側ゲートウェイの基本構成を、erubyテンプレートとして記述しています。
書式は以下を参照のこと

- [標準添付ライブラリ紹介 【第 10 回】 ERB](https://magazine.rubyist.net/articles/0017/0017-BundledLibraries.html)
