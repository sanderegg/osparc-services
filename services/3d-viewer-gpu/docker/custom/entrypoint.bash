#!/bin/bash
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

echo
echo "current directory is ${PWD}"

echo
echo "set up python 3"
export PATH="${PYENV_ROOT}/bin:$PATH"
eval "$(pyenv init -)"
python -V
pip -V

if [[ -v CREATE_DUMMY_TABLE ]];
then
    pushd /home/root/scripts/dy_services_helpers; pip3 install -r requirements.txt; popd
    # in dev mode, data located in mounted volume /test-data are uploaded to the S3 server
    # also a fake configuration is set in the DB to simulate the osparc platform
    echo
    echo "development mode, init dummy pipeline..."
    # in style: pipelineid,nodeuuid
    result="$(python3 scripts/dy_services_helpers/platform_initialiser.py "${USE_CASE_CONFIG_FILE}" --folder "${TEST_DATA_PATH}")";
    echo "Received result of $result";
    IFS=, read -ra array <<< "$result";
    echo "Received result pipeline id of ${array[0]}";
    echo "Received result node uuid of ${array[1]}";
    # the fake SIMCORE_NODE_UUID is exported to be available to the service
    export SIMCORE_NODE_UUID="${array[1]}";
    export SIMCORE_PROJECT_ID="${array[0]}"
    # we need to copy the handlers in the correct folder (only for debug mode to prevent masking files)
    cp handlers/*.rpy /opt/paraview/share/paraview-5.6/web/visualizer/www/
fi

# patch paraview
echo
echo "patching paraviewweb to allow for rpy scripts to run..."
docker/patch_paraview.bash

# set default parameters (note that port is the server local port, and host is used for the websocket location)
echo
echo "setting up visualizer options..."
visualizer_options=(--content /opt/paraview/share/paraview-5.6/web/visualizer/www/ \
                    --host 0.0.0.0 \
                    --port "80" \
                    --timeout 20000 \
                    --no-built-in-palette \
                    --color-palette-file /home/root/config/s4lColorMap.json \
                    --settings-lod-threshold 5 \
                    )



# show additional debugging parameters on demand
if [[ ${PARAVIEW_DEBUG} != 0 ]]; then
    echo
    echo "setting paraview debug mode on"
    visualizer_options+=(--debug)
fi


if [ "${DY_BOOT_OPTION_BOOT_MODE}" -eq "0" ]; then
    set -e
    export PARAVIEW_INPUT_PATH=/data/A
    set +e
    echo
    echo "setting input folder as data folder --> --data PARAVIEW_INPUT_PATH: ${PARAVIEW_INPUT_PATH}"
    echo "INFO: In the dy-sidecars inputs might be pulled after the entrypoint.sh is executed. Inputs might not be present when the binary of paraview is executed."
    visualizer_options+=(--data "${PARAVIEW_INPUT_PATH}")
    visualizer_options+=(--load-file "${SIMCORE_STATE_FILE}")
elif [ "${DY_BOOT_OPTION_BOOT_MODE}" -eq "1" ] && [ -f /data_baked/3Danatomical/"${SIMCORE_STATE_FILE}" ]; then
    set -e
    export PARAVIEW_INPUT_PATH=/data_baked/3Danatomical/
    set +e
    echo
    echo "setting autoload of 3D Anatomical data"
    visualizer_options+=(--load-file "${SIMCORE_STATE_FILE}")
    visualizer_options+=(--data "${PARAVIEW_INPUT_PATH}")
elif [ "${DY_BOOT_OPTION_BOOT_MODE}" -eq "2" ] && [ -f /data_baked/3Dem/"${SIMCORE_STATE_FILE}" ]; then
    set -e
    export PARAVIEW_INPUT_PATH=/data_baked/3Dem/
    set +e
    echo
    echo "setting autoload of 3D EM data"
    visualizer_options+=(--load-file "${SIMCORE_STATE_FILE}")
    visualizer_options+=(--data "${PARAVIEW_INPUT_PATH}")
elif [ "${DY_BOOT_OPTION_BOOT_MODE}" -eq "3" ] && [ -f /data_baked/NeurofaunaRat/"${SIMCORE_STATE_FILE}" ]; then
    set -e
    export PARAVIEW_INPUT_PATH=/data_baked/NeurofaunaRat/
    set +e
    echo
    echo "setting autoload of NeurofaunaRat data"
    visualizer_options+=(--load-file "${SIMCORE_STATE_FILE}")
    visualizer_options+=(--data "${PARAVIEW_INPUT_PATH}")
else
    echo
    echo "WARNING: INVALID BOOTMODE: {${DY_BOOT_OPTION_BOOT_MODE}}. FALLING BACK TO DEFAULTS."
    set -e
    export PARAVIEW_INPUT_PATH=/data/A
    set +e
    visualizer_options+=(--data "${PARAVIEW_INPUT_PATH}")
    visualizer_options+=(--load-file "${SIMCORE_STATE_FILE}")
fi

# start server
echo
echo "starting paraview on localhost..."
echo "using " "${visualizer_options[@]}"
/opt/paraview/bin/pvpython -dr --mpi \
    /opt/paraview/share/paraview-5.6/web/visualizer/server/pvw-visualizer.py "${visualizer_options[@]}"
