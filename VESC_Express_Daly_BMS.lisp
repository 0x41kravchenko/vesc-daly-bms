; Daly Smart BMS (BLE UART) integration with VESC using VESC Express
; DALY UART protocol implementation taken from https://github.com/maland16/daly-bms-uart.git
; Copyright 2026 0x41kravchenko

; Daly defines
(def XFER_BUFFER_LENGTH 13)
(def MIN_NUMBER_CELLS 1)
(def MAX_NUMBER_CELLS 48)
(def MIN_NUMBER_TEMP_SENSORS 1)
(def MAX_NUMBER_TEMP_SENSORS 16)

; Daly commands
(def VOUT_IOUT_SOC 0x90)
(def MIN_MAX_CELL_VOLTAGE 0x91)
(def MIN_MAX_TEMPERATURE 0x92)
(def DISCHARGE_CHARGE_MOS_STATUS 0x93)
(def STATUS_INFO 0x94)
(def CELL_VOLTAGES 0x95)
(def CELL_TEMPERATURE 0x96)
(def CELL_BALANCE_STATE 0x97)
(def FAILURE_CODES 0x98)
;(def DISCHRG_FET 0xD9)
;(def CHRG_FET 0xDA)
(def BMS_RESET 0x00)

; Daly values variables
; data from 0x90
(def packVoltage 0)              ; Total pack voltage (0.1 V)
(def packCurrent 0)              ; Current in (+) or out (-) of pack (0.1 A)
(def packSOC 0)                  ; State Of Charge
; data from 0x93
(def chargeDischargeStatus "")    ; charge/discharge status (0 stationary, 1 charge, 2 discharge)
(def chargeFetState 0)           ; charging MOSFET status
(def disChargeFetState 0)        ; discharge MOSFET state
(def bmsHeartBeat 0)             ; BMS life (0~255 cycles)?
(def resCapacitymAh 0)           ; residual capacity mAH
; data from 0x94
(def numberOfCells 0)            ; Cell count
(def numOfTempSensors 0)         ; Temp sensor count
(def chargeState 0)              ; charger status 0 = disconnected 1 = connected
(def loadState 0)                ; Load Status 0=disconnected 1=connected
;; bool dIO[8];                  ; No information about this - NOT IMPLEMENTED
(def bmsCycles 0)                ; charge / discharge cycles
; data from 0x95
(def cellVmV (bufcreate 96))     ; Store Cell Voltages (mV) ; Max 48 cells 2 bytes for each ; 48 to save space
; data from 0x96
(def cellTemperature (bufcreate 32)) ; // array of cell Temperature sensors ; Max 16 sensors 2 bytes for each ; 3*2 to save space
(def communication_error "")
(def maxCellVmV 5.0) ; Track for sanity check

;(lbm-set-quota 100) ; doesn't help? -10 error
(sleep 2)
(gpio-configure 10 'pin-mode-out)
(gpio-write 10 1) ; BMS switch/activate signal ON, optoisolator anode
(sleep 0.5)
(gpio-write 10 0) ; BMS switch/activate signal OFF
(uart-start 0 20 21 9600) ; Daly UART (instead of Daly BLE module) connected to 20, 21 of VESC Express
; AVOID CONNECTING UART GND since on Daly BMS UART GND is connected to B- meaning if BMS will trigger discharge protection current will flow via thin UART GND wire.

(def read_arr (bufcreate XFER_BUFFER_LENGTH))
(def write_arr (bufcreate XFER_BUFFER_LENGTH))
(def checksum 0)
(bufset-u8 write_arr 0 0xA5)
(bufset-u8 write_arr 1 0x40)
(bufset-u8 write_arr 3 0x08)

(defun daly-validateChecksum () {
    (setq checksum 0)
    (loopfor i 0 (< i (- XFER_BUFFER_LENGTH 1)) (+ i 1) { ; All buffer bytes except last one (checksum)
        (setq checksum (+ checksum (bufget-u8 read_arr i)))
    })
    (setq checksum (mod checksum 256))
    ;(print (list checksum (bufget-u8 read_arr (- XFER_BUFFER_LENGTH 1))))
    (= checksum (bufget-u8 read_arr (- XFER_BUFFER_LENGTH 1)))
})

(defunret daly-isRxEqTx () {
    (loopfor i 0 (< i XFER_BUFFER_LENGTH) (+ i 1) {
        (if (!= (bufget-u8 write_arr i) (bufget-u8 read_arr i)) (return false))
    })
    true
})

;(defun daly-uart-resync () {
    ; Resync caused new issue: cmd handlers were parsing each others packets after resync, to fix it's needed to parse cmd_id from response and handle it
    ;(var tmp (bufcreate 32))
    ;(uart-read-until tmp 1 0 0xA5)
;})

;(defun daly-uart-drain () {
    ; Same issue as from above: cmd handlers parsing others packets
    ;(var tmp (bufcreate 64))
    ;(loopwhile (> (uart-read tmp 64 nil nil 0) 0) {
        ; discard
    ;})
;})

; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ IMPLEMENT ASYNC PACKET HANDLERS BASED ON CMD_ID AND PACKET INDEX (cells, temps responses) ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

(defunret daly-get-uart-data (cmd_id) {
    ;(uart-read-bytes read_arr XFER_BUFFER_LENGTH 0)
    (uart-read read_arr XFER_BUFFER_LENGTH nil nil 3)
    (print (list"Received:" read_arr))
    ;(print (daly-validateChecksum))
    (if (not (daly-validateChecksum)) {
        (print "Error: Checksum validation failed")
        ; Empty RX buffer??? Bad data gets into variables after numerous corrupted packages
        ; "Flush" / hard reload UART to empty rx buffer, no bueno but it works in comparison to resync and drain approaches
        (uart-stop)
        (uart-start 0 20 21 9600)
        ;(daly-uart-resync)
        ;(daly-uart-drain)
        (return nil)
    })
    (if (daly-isRxEqTx) {
        (print "Error: RX and TX buffers are equal. BMS is asleep?")
        (return nil)
    })
    (if (!= cmd_id (bufget-u8 read_arr 2)) {
        (print "Error: Received packet designated for another handler/parser, skipping")
        (return nil)
        })
    true
})

(defun daly-send-command (cmd_id) {
    (bufset-u8 write_arr 2 cmd_id)

    (setq checksum 0)
    (loopfor i 0 (< i (- XFER_BUFFER_LENGTH 1)) (+ i 1) {; All buffer bytes except last one (checksum)
         (setq checksum (+ checksum (bufget-u8 write_arr i)))
    })
    (setq checksum (mod checksum 256))
    ;(print checksum)
    (bufset-u8 write_arr 12 checksum) ; Checksum

    ;(print (list "Send command:" write_arr))
    (uart-write write_arr)
})

(defunret daly-getDischargeChargeMosStatus () {
    (daly-send-command DISCHARGE_CHARGE_MOS_STATUS)
    (if (not (daly-get-uart-data DISCHARGE_CHARGE_MOS_STATUS)) (return nil))
    (if (= (bufget-u8 read_arr 4 ) 0) (setq chargeDischargeStatus "Stationary"))
    (if (= (bufget-u8 read_arr 4 ) 1) (setq chargeDischargeStatus "Charge"))
    (if (= (bufget-u8 read_arr 4 ) 2) (setq chargeDischargeStatus "Discharge"))
    (setq chargeFetState (bufget-u8 read_arr 5))
    (setq disChargeFetState (bufget-u8 read_arr 6))
    (setq bmsHeartBeat (bufget-u8 read_arr 7))
    (setq resCapacitymAh (bitwise-or (bitwise-or (bitwise-or (shl (bufget-u8 read_arr 8) 0x18) (shl (bufget-u8 read_arr 9) 0x10)) (shl (bufget-u8 read_arr 10) 0x08)) (bufget-u8 read_arr 11)))
})

(defunret daly-getPackMeasurements () {
    (daly-send-command VOUT_IOUT_SOC)
    (if (not (daly-get-uart-data VOUT_IOUT_SOC)) (return nil))
    (setq packVoltage (/ (to-float (bitwise-or (shl (bufget-u8 read_arr 4) 8) (bufget-u8 read_arr 5))) 10.0f32))
    ; The current measurement is given with a 30000 unit offset
    (setq packCurrent (/ (to-float (- (bitwise-or (shl (bufget-u8 read_arr 8) 8) (bufget-u8 read_arr 9)) 30000)) 10.0f32))
    (setq packSOC (/ (to-float (bitwise-or (shl (bufget-u8 read_arr 10) 8) (bufget-u8 read_arr 11))) 10.0f32))
})

(defunret daly-getCellVoltages () {
    (def cellNo 0)
    (def cellmV 0)
    (def frameId 0)
    (daly-send-command CELL_VOLTAGES)
    (loopfor i 0 (< i (ceil (/ numberOfCells 3.0))) (+ i 1) {
        (if (not (daly-get-uart-data CELL_VOLTAGES)) (return nil))
        (setq frameId (bufget-u8 read_arr 4))
        (loopfor j 0 (< j 3) (+ j 1) {
            (setq cellNo (+ (* (- frameId 1) 3) j))
            (setq cellmV (bitwise-or (shl (bufget-u8 read_arr (+ (+ 5 j) j)) 8) (bufget-u8 read_arr (+ (+ 6 j) j))))
            (bufset-u16 cellVmV (+ cellNo cellNo) cellmV) ; write value to byte 0 and 1 as uint16 and so on
            (print (list maxCellVmV cellmV))
            (setq maxCellVmV (if (< maxCellVmV cellmV) cellmV maxCellVmV))
            (if (>= cellNo numberOfCells) (break t))
        })
    })

})

(defunret daly-getStatusInfo () {
    ; Provides number of cells and temp sensors that are used in other logic. This function should be called first
    (daly-send-command STATUS_INFO)
    (if (not (daly-get-uart-data STATUS_INFO)) (return nil))
    (setq numberOfCells (bufget-u8 read_arr 4))
    (setq numOfTempSensors (bufget-u8 read_arr 5))
    (setq chargeState (bufget-u8 read_arr 6))
    (setq loadState (bufget-u8 read_arr 7))
    ; dIO is in byte 8, skipping since not implemented here
    (setq bmsCycles (bitwise-or (shl (bufget-u8 read_arr 9) 8) (bufget-u8 read_arr 10)))
})

(defunret daly-getCellTemperature () {
    ; depends on daly-getStatusInfo - call that one before this function
    (def sensorNo 0)
    (def frameId 0)
    (daly-send-command CELL_TEMPERATURE)
    (loopfor i 0 (< i (ceil (/ numOfTempSensors 7.0))) (+ i 1) {
        (if (not (daly-get-uart-data CELL_TEMPERATURE)) (return nil))
        (setq frameId (bufget-u8 read_arr 4))
        (loopfor j 0 (< j 7) (+ j 1) {
            (setq sensorNo (+ (* (- frameId 1) 7) j))
            (bufset-u16 cellTemperature (+ sensorNo sensorNo) (- (bufget-u8 read_arr (+ 5 j)) 40)) ; write value to byte 0 and 1 as uint16 and so on
            (if (>= (+ sensorNo 1) numOfTempSensors) (break t))
        })
    })
})

(defun daly-get-values () {
    (daly-getStatusInfo)
    (sleep 0.1)
    (daly-getDischargeChargeMosStatus)
    (sleep 0.1)
    (daly-getPackMeasurements)
    (sleep 0.1)
    (daly-getCellVoltages)
    (sleep 0.1)
    (daly-getCellTemperature)

    (print "===== DATA =====")

    (print (str-from-n packVoltage "packVoltage %.2f V"))
    (print (str-from-n packCurrent "packCurrent %.2f A"))
    (print (str-from-n packSOC "packSOC: %.2f"))

    (print (str-merge "chargeDischargeStatus: " chargeDischargeStatus))
    (print (str-from-n chargeFetState "chargeFetState: %d"))
    (print (str-from-n disChargeFetState "disChargeFetState: %d"))
    (print (str-from-n bmsHeartBeat "bmsHeartBeat: %d"))
    (print (str-from-n resCapacitymAh "resCapacitymAh: %d mAh"))
    ;(print "cellVmV" cellVmV)
    (loopfor i 0 (< i numberOfCells) (+ i 1) {
        (print (str-merge  "Cell #" (str-from-n i) " " (str-from-n (bufget-u16 cellVmV (+ i i)))  " mV"))
    })

    (print (str-from-n numberOfCells "numberOfCells: %d"))
    (print (str-from-n numOfTempSensors "numOfTempSensors: %d"))
    (print (str-from-n chargeState "chargeState: %d"))
    (print (str-from-n loadState "loadState: %d"))
    (print (str-from-n bmsCycles "bmsCycles: %d"))

    ;(print "cellTemperature" cellTemperature)
    (loopfor i 0 (< i numOfTempSensors) (+ i 1) {
        (print (str-merge  "Temp sensor #" (str-from-n i) " " (str-from-n (bufget-u16 cellTemperature (+ i i)))  " C"))
    })

    (print (str-from-n maxCellVmV "maxCellVmV: %d mV"))
})

;(daly-get-values) ; 1 call to debug



(defun update-bms-values () {
    (loopfor i 0 (< i numberOfCells) (+ i 1) {
        (set-bms-val 'bms-v-cell i (/ (bufget-u16 cellVmV (+ i i)) 1000.0))
    })
    (set-bms-val 'bms-v-tot packVoltage)
    (set-bms-val 'bms-i-in-ic (* packCurrent -1)) ; Inverting because in VESC negative means charging
    (loopfor i 0 (< i numOfTempSensors) (+ i 1) {
        (set-bms-val 'bms-temps-adc i (bufget-u16 cellTemperature (+ i i)))
    })

    (set-bms-val 'bms-soc (/ packSOC 100.0)) ; VESC interprets 1.0 as 100% SoC ; Daly SOC is way off, is it because BMS is connected as charge only and cannot monitor discharge current?

    ; TODO IMPLEMENT:
    ; ??? ->? (get-bms-val 'bms-msg-age) ; Age of last message from BMS in seconds. Is this read only?
    ; CELL_BALANCE_STATE cmd_id -> (get-bms-val 'bms-bal-state 2) ; Cell 3 balancing state. 0: not balancing, 1: balancing
    ; MIN_MAX_TEMPERATURE cmd_id-> (get-bms-val 'bms-temp-cell-max) ; Maximum cell temperature
    ; ERRORS -> (get-bms-val 'bms-status) ; Status string (added in 6.06)

    (send-bms-can)
})





(if (!= (str-cmp (to-str (sysinfo 'hw-type)) "hw-express") 0) {
    (exit-error "Not running on hw-express")
})

(daly-get-values) ; Initiate values
(set-bms-val 'bms-cell-num numberOfCells) ; set bms-cell-num before setting bms-v-cell
(set-bms-val 'bms-temp-adc-num numOfTempSensors) ; set bms-temp-adc-num before setting bms-temps-adc

(loopwhile-thd 200 t {
        (daly-get-values)
        (update-bms-values)
        (sleep 2)
})

; Reveiving same as sent when BMS goes to sleep (is sleeping)
;"Send command:"
;[165 64 147 8 0 0 0 0 0 0 0 0 128]
;"Received:"
;[165 64 147 8 0 0 0 0 0 0 0 0 128]
; ^ UART timeout??? Check uart-read response?
