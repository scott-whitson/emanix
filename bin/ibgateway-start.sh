#!/usr/bin/env bash
export DISPLAY=:50

# Critical: JavaFX module path
export JAVA_TOOL_OPTIONS="--module-path=/tmp/javafx-sdk/javafx-sdk-17.0.11/lib --add-modules=javafx.web,javafx.media,javafx.swing,javafx.graphics,javafx.controls"

# Run IBC gateway
export IBC_INI=/etc/ibgateway/ibc-config.ini
export IBC_PATH=/opt/ibc
export TWS_PATH=/opt/ibgateway/jts
export TWS_SETTINGS_PATH=/opt/ibgateway/jts
export JAVA_PATH=/home/scott/.nix-profile/bin

/opt/ibc/gatewaystart.sh -inline \
	--ibc-ini=/etc/ibgateway/ibc-config.ini \
	--tws-path=/opt/ibgateway/jts \
	--tws-settings-path=/opt/ibgateway/jts
