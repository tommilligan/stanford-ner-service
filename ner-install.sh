#!/bin/bash
# Full setup for NER service

# Config variables
versionName="stanford-ner-2017-06-09"
zipFile="$versionName.zip"
autogeneratedComment="This file is autogenerated by stanford-ner-service/ner-install.sh"

# Log to stderr
function log() {
    printf "ner-install|$1\n" >&2
}

# We need a port number to write the correct service
log "Checking environment variables"
portNumber=${STANFORD_NER_PORT:?}


if [ $# -eq 1 ]; then
    # If an argument is given, treat it as the target directory
    changeTo="$1"
    echo "Changing directory to $changeTo"
    cd "$changeTo"
elif [ $# -gt 1 ]; then
    # More than 1 argument is invalid
    log "ERROR: Usage: ner-install [output_directory]"
    exit 1
fi


# Global variables
# The directory to install to
workingDirectory="$(pwd)"


# Get NER source
# If we dont already hav a zipfile, download
test -f "$zipFile"
if [ $? -eq 0 ]; then
    log "Using existing NER archive $zipfile"
else
    log "Fetching NER archive"
    wget "https://nlp.stanford.edu/software/$zipFile"
fi
# Always unzip from the archive
log "Removing previous folder"
rm -rf "$versionName"
log "Unpacking archive"
unzip "$zipFile"


# Make sure we have Java 8
# is default java version 8
log "Looking for Java 8"
executable="java8"
java -version 2>&1 | awk '/version/{print $NF}' | grep '"1.8.'
if [ $? -eq 0 ]; then
    log "Default java points to java8"
    executable="java"
else
    # or is java8 installed
    java8 -version
    if [ $? -eq 0 ]; then
        log "java8 found"
    else
        log "Need to install java8"
        sudo yum install java-1.8.0-openjdk.x86_64 -y
    fi
fi
log "Using java executable '$executable'"


# Write server script
serverScript="$workingDirectory/ner-server.sh"
log "Writing server script to $serverScript"
cat << EOF > $serverScript
#!/bin/sh

# $autogeneratedComment

$executable -mx1000m -cp "$workingDirectory/$versionName/stanford-ner.jar:$workingDirectory/$versionName/lib/*" edu.stanford.nlp.ie.NERServer  -loadClassifier "$workingDirectory/$versionName/classifiers/english.muc.7class.distsim.crf.ser.gz" -port $portNumber -outputFormat inlineXML
EOF

# Write service unit
serviceUnitName="stanford-nerd"
serviceUnit="$workingDirectory/$serviceUnitName"
log "Writing service unit to $serviceUnit"
cat << EOF > $serviceUnit
#!/bin/bash
#
# /etc/init.d/$serviceUnitName
#
# chkconfig: 235 20 80
# description: Stanford NER HTTP service daemon.
#

# $autogeneratedComment

# Source function library.
. /etc/init.d/functions

start() {
        echo -n "Starting $serviceUnitName: "
        touch /var/lock/subsys/$serviceUnitName
        daemon $serverScript
        return \$?
}

stop() {
        echo -n "Shutting down $serviceUnitName: "
        rm -f /var/lock/subsys/$serviceUnitName
        killproc $serverScript
        return \$?
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    condrestart)
        [ -f /var/lock/subsys/$serviceUnitName ] && restart || :
        ;;
    *)
        echo "Usage: $serviceUnitName {start|stop|restart|condrestart}"
        exit 1
        ;;
esac
exit \$?
EOF

# Make executable
log "Marking generated files as executable" 
chmod a+x "$serverScript" "$serviceUnit"


# Add service to system and enable
# Do not need to start, will be started either by user, restart or post-install hook
log "Installing Stanford NER service as $serviceUnitName"
cp "$serviceUnit" "/etc/init.d/"

log "Enabling service"
chkconfig --add "$serviceUnitName" 
chkconfig --level 235 "$serviceUnitName" on 

log "Installation complete: run with /etc/init.d/stanford-nerd start"
