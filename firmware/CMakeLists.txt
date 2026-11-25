#===============================================================================
# @brief    cmake file of EEG Brain Ring sample.
#===============================================================================

set(SOURCES_LIST
    ${CMAKE_CURRENT_SOURCE_DIR}/eeg_ring.c
    ${CMAKE_CURRENT_SOURCE_DIR}/eeg_core/eeg_sensor.c
    ${CMAKE_CURRENT_SOURCE_DIR}/eeg_core/eeg_frame.c
    ${CMAKE_CURRENT_SOURCE_DIR}/ble_eeg_server/ble_eeg_server.c
    ${CMAKE_CURRENT_SOURCE_DIR}/ble_eeg_server/ble_eeg_server_adv.c
    ${CMAKE_CURRENT_SOURCE_DIR}/sle_eeg_server/sle_eeg_server.c
    ${CMAKE_CURRENT_SOURCE_DIR}/sle_eeg_server/sle_eeg_server_adv.c
)

if(DEFINED CONFIG_EEG_SENSOR_MODE_NEUROSKY)
    list(APPEND SOURCES_LIST ${CMAKE_CURRENT_SOURCE_DIR}/eeg_core/eeg_neurosky.c)
elseif(DEFINED CONFIG_EEG_SENSOR_MODE_ADC)
    list(APPEND SOURCES_LIST ${CMAKE_CURRENT_SOURCE_DIR}/eeg_core/eeg_adc.c)
endif()

set(HEADER_LIST
    ${CMAKE_CURRENT_SOURCE_DIR}/eeg_core
    ${CMAKE_CURRENT_SOURCE_DIR}/ble_eeg_server
    ${CMAKE_CURRENT_SOURCE_DIR}/sle_eeg_server
)

set(SOURCES "${SOURCES}" ${SOURCES_LIST} PARENT_SCOPE)
set(PUBLIC_HEADER "${PUBLIC_HEADER}" ${HEADER_LIST} PARENT_SCOPE)
