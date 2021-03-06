PROJECT = emq_plugin_apinf
PROJECT_DESCRIPTION = EMQ Apinf Plugin
PROJECT_VERSION = 2.1.1

BUILD_DEPS = emqttd esio uuid
dep_emqttd = git https://github.com/emqtt/emqttd master
dep_esio	 = git https://github.com/frenchbread/esio master
dep_uuid   = git https://github.com/avtobiff/erlang-uuid master

TEST_DEPS = cuttlefish
dep_cuttlefish = git https://github.com/basho/cuttlefish master

COVER = true

include erlang.mk

app:: rebar.config

app.config::
	cuttlefish -l info -e etc/ -c etc/emq_plugin_apinf.conf -i priv/emq_plugin_apinf.schema -d data
