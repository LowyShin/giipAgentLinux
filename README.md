## Introduce

This repository is Agent files for client connect to giip Service.

for Windows : https://github.com/LowyShin/giipAgentWin

### Download giipAgent

```shell
git clone https://github.com/LowyShin/giipAgentLinux.git
```

### Configure client environment

copy giipAgent.cnf to upper directory
```shell
cp giipAgentLinux/giipAgent.cnf ./
```

```shell
vi giipAgent.cnf
```

Put your Secret Key and LSSN from giip web UI

If you are first time in giip service, you need to registration by giip web(https://giipasp.azurewebsites.net) service. it is all free(except third party services)!

You may add project and service by giip web sites, then you can get Secret key on service management page.

You may get LSSN from logical machine management page when you select your project you made. 

Then save it.


### Register cron

Requirement module

* dos2unix
```sh
yum install -y dos2unix
```

Add crontab

```sh
cd giipAgentLinux

sh giipcronreg.sh
```

## Fully automate servers, robots, IoT by giip.

* Go to giip service Page : http://giipasp.azurewebsites.net
* Documentation : https://github.com/LowyShin/giip/wiki
* Sample automation scripts : https://github.com/LowyShin/giip/tree/gh-pages/giipscripts

## GIIP Token uses for engineers!

See more : https://github.com/LowyShin/giip/wiki

* Token exchanges : https://tokenjar.io/GIIP
* Token exchanges manual : https://www.slideshare.net/LowyShin/giipentokenjario-giip-token-trade-manual-20190416-141149519
* GIIP Token Etherscan : https://etherscan.io/token/0x33be026eff080859eb9dfff6029232b094732c52

If you want get GIIP, contact us any time!

## Other Languages

* [English](https://github.com/LowyShin/giip/wiki)
* [日本語](https://github.com/LowyShin/giip-ja/wiki)
* [한국어](https://github.com/LowyShin/giip-ko/wiki)

## Contact

* [Contact Us](https://github.com/LowyShin/giip/wiki/Contact-Us)

