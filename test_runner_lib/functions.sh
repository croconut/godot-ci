# Parse XML with bash-only: 
# https://stackoverflow.com/questions/893585/how-to-parse-xml-in-bash/2608159#2608159
read_xml_dom () { local IFS=\> ; read -d \< E C ;}

check_if_version_four() {
    local version=$GODOT_VERSION
    local version_three=3
 
    # Remove the leading 'v' character if present
    version=${version#v}
 
    # Extract the major version number from the version string
    local current_major_version=$(echo "$version" | cut -d. -f1)
 
    if [ "$current_major_version" -gt "$version_three" ]; then
        # v4+ behavior
        IS_VERSION_FOUR=1
    fi
}

delete_godot() {
    rm -rf ${CUSTOM_DL_PATH}/${FULL_GODOT_NAME_EXT}
    rm -f ${CUSTOM_DL_PATH}/${FULL_GODOT_NAME_EXT}.zip
}

add_gut_rebuilder() {
    mkdir -p ./addons/gut/.cli_add
    mv -n /__rebuilder.gd ./addons/gut/.cli_add
    mv -n /__rebuilder_scene.tscn ./addons/gut/.cli_add
}

delete_gut_rebuilder() {
    rm -rf ./addons/gut/.cli_add/__rebuilder.gd
    rm -rf ./addons/gut/.cli_add/__rebuilder_scene.tscn
}

generate_dl_url() {
    if [ "$RELEASE_TYPE" = "stable" ]; then
        GODOT_URL_PATH_SUBDIR=""
    else
        # if not stable, then it's a release candidate or beta
        # Those are located in a subdirectory of the release type
        # example: /beta1, /rc1, etc.
        GODOT_URL_PATH_SUBDIR="/${RELEASE_TYPE}"
    fi
    # This is the path to the godot version hosted on tuxfamily
    # example: 3.2.3/, 3.2.3/beta1/, etc.
    GODOT_URL_PATH="${GODOT_VERSION}${GODOT_URL_PATH_SUBDIR}/"

    if [ "$IS_MONO" = "true" ]; then
        # mono builds are in a subdirectory of the godot version
        # example: 3.2.3/mono/, 3.2.3/beta1/mono/, etc.
        GODOT_URL_PATH="${GODOT_URL_PATH}mono/"
    fi

    FULL_GODOT_NAME="Godot_v${GODOT_VERSION}-${RELEASE_TYPE}"
    if [[ "$IS_VERSION_FOUR" -eq "1" ]]; then
        echo "Version 4 detected"
        # v4+ behavior
        # does not need a special headless binary
        # and has a new extension (_x86_64 | .x86_64)
        if [ "$IS_MONO" = "true" ]; then
            FULL_GODOT_NAME="${FULL_GODOT_NAME}_mono_linux"
            FULL_GODOT_NAME_EXT="${FULL_GODOT_NAME}_x86_64"
        else
            FULL_GODOT_NAME="${FULL_GODOT_NAME}_linux"
            FULL_GODOT_NAME_EXT="${FULL_GODOT_NAME}.x86_64"
        fi
    else
        echo "Version 3 detected"
        # v3 behavior
        # must specify the headless binary
        # and the (_64 | .64) extension
        if [ "$IS_MONO" = "true" ]; then
            FULL_GODOT_NAME="${FULL_GODOT_NAME}_mono_linux_headless"
            FULL_GODOT_NAME_EXT="${FULL_GODOT_NAME}_64"
        else
            FULL_GODOT_NAME="${FULL_GODOT_NAME}_linux_headless"
            FULL_GODOT_NAME_EXT="${FULL_GODOT_NAME}.64"
        fi
    fi

    # Apply the generated path & name to the download url
    DL_URL="https://downloads.tuxfamily.org/godotengine/${GODOT_URL_PATH}${FULL_GODOT_NAME_EXT}.zip"

    if [ "$CUSTOM_GODOT_DL_URL" != "" ]; then
        DL_URL="$CUSTOM_GODOT_DL_URL"
    fi
}

perform_download() {
    mkdir -p ${CUSTOM_DL_PATH}
    echo "downloading godot from ${DL_URL} ..."
    yes | wget -q ${DL_URL} -P ${CUSTOM_DL_PATH}
}

unzip_godot() {
    mkdir -p ~/.cache
    mkdir -p ~/.config/godot
    echo "unzipping ..."
    yes | unzip -q ${CUSTOM_DL_PATH}/${FULL_GODOT_NAME_EXT}.zip -d ${CUSTOM_DL_PATH}
    chmod -R 777 ${CUSTOM_DL_PATH}
}

download_godot() {
    # Generate the URL based on the version and release type
    generate_dl_url

    # Just in case there was a broken godot from a previous run
    delete_godot

    # Download the godot binary into the custom_dl_folder
    perform_download

    # Unzip the godot binary
    unzip_godot
}

generate_run_options() {
    RUN_OPTIONS="-s addons/gut/gut_cmdln.gd"
    RUN_OPTIONS="${RUN_OPTIONS} -gdir=${TEST_DIR}"
    RUN_OPTIONS="${RUN_OPTIONS} -ginclude_subdirs"
    RUN_OPTIONS="${RUN_OPTIONS} -gjunit_xml_file=./${RESULT_OUTPUT_FILE}"
    RUN_OPTIONS="${RUN_OPTIONS} -gexit"

    # these are mutually exclusive - direct scenes cannot take a config file but they can
    # have all those options set on the scene itself anyways
    if [ "$DIRECT_SCENE" != "false" ]; then
        RUN_OPTIONS="${DIRECT_SCENE}"
    elif [ "$CONFIG_FILE" != "res://.gutconfig.json" ]; then
        RUN_OPTIONS="${RUN_OPTIONS} -gconfig=${CONFIG_FILE}"
    fi

    if [ "$IS_VERSION_FOUR" -eq "1" ]; then
        # v4+ behavior
        # you must use the --headless argument 
        # rather than use a headless binary
        RUN_OPTIONS="${RUN_OPTIONS} --headless"
    fi
}

check_by_test() {
    FAILURE_REGEX="failures=\"([0-9]+)\""
    TESTS_REGEX="tests=\"([0-9]+)\""

    while read_xml_dom; do
        if [[ $E =~ ^testsuites ]]; then
            if [[ $E =~ $FAILURE_REGEX ]]
            then
                FAILED="${BASH_REMATCH[1]}"
            fi

            if [[ $E =~ $TESTS_REGEX ]]
            then
                TESTS="${BASH_REMATCH[1]}"
            fi

            break
        fi
    done < ./${RESULT_OUTPUT_FILE}

    echo "XML: Tests Detected: ${TESTS}"
    echo "XML: Failed Tests: ${FAILED}"
}

check_by_assert() {
    while read_xml_dom; do
        ASSERT_REGEX="assertions=\"([0-9]+)\""

        if [[ $E =~ $ASSERT_REGEX ]]
        then
            ((TESTS+=${BASH_REMATCH[1]}))
        fi

        if [[ $E =~ ^failure ]]
        then
            ((FAILED+=1))
        fi
    done < ./${RESULT_OUTPUT_FILE}

    echo "XML: Asserts Detected: ${TESTS}"
    echo "XML: Failed Asserts: ${FAILED}"
}

calculate_pass_rate() {
    passrate=".0"
    endmsg=""
    if [ "$TESTS" -eq "0" ]; then
        exitval=1
        endmsg="Tests failed due to timeout or there were no tests to run\n"
    else
        passrate=$(echo "scale=3; ($TESTS-$FAILED)/$TESTS" | bc -l)
        echo -e "\n${passrate} pass rate\n"
        if (($(echo "$passrate >= $MINIMUM_PASSRATE" | bc -l))); then
            exitval=0
        else
            endmsg="Tests failed due to low passrate\n"
            exitval=1
        fi

        if [[ "$MAX_FAILS" != "false" ]]; then
            if [[ "$FAILED" -gt "$MAX_FAILS" ]]; then
                endmsg="Tests failed due to fail count of ${FAILED} exceeding maximum of ${MAX_FAILS}"
                exitval=1
            fi
        fi
    fi

    if [ "$endmsg" != "" ]; then
        echo -e "${endmsg}"
    fi
}

# When the mono builds are extracted, they are in a subdirectory of the zip
# Furthermore, the executable name is the same as the linux name, but 
# the folder name is different... so we need to account for that
# This function generates the path to the executable
generate_godot_executable_path() {
    GODOT_EXECUTABLE="./${CUSTOM_DL_PATH}/${FULL_GODOT_NAME_EXT}"
    if [ "$IS_MONO" = "true" ]; then
        # mono builds are in a subdirectory of the extracted godot zip
        # example: file_name_x86_64/file_name.x86_64
        if [ "$IS_VERSION_FOUR" -eq "1" ]; then
            GODOT_EXECUTABLE="${GODOT_EXECUTABLE}/${FULL_GODOT_NAME}.x86_64"
        else
            GODOT_EXECUTABLE="${GODOT_EXECUTABLE}/${FULL_GODOT_NAME}.64"
        fi
    fi
}

run_tests() {
    set +e

    add_gut_rebuilder
    generate_run_options

    generate_godot_executable_path

    # need to init the imports
    # workaround for -e -q and -e with timeout failing
    # credit: https://github.com/Kersoph/open-sequential-logic-simulation/pull/4/files

    # Added --headless to the import step to account for v4+ behavior
    # this argument on v3.x is simply ignored
    echo "running imports ..."
    timeout ${IMPORT_TIME} "${GODOT_EXECUTABLE}" --headless --editor addons/gut/.cli_add/__rebuilder_scene.tscn
    # After the imports are done, we can run the tests
    echo "running tests ..."
    timeout ${TEST_TIME} "${GODOT_EXECUTABLE}" ${RUN_OPTIONS}

    delete_gut_rebuilder
    delete_godot
}

analyze_test_results() {
    if [ "$ASSERT_CHECK" != "false" ]; then
        check_by_assert
    else
        check_by_test
    fi

    rm -f ./${RESULT_OUTPUT_FILE}
    calculate_pass_rate
}