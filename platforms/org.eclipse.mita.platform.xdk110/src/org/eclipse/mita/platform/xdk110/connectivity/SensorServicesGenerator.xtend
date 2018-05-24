/********************************************************************************
 * Copyright (c) 2017, 2018 Bosch Connected Devices and Solutions GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 *
 * Contributors:
 *    Bosch Connected Devices and Solutions GmbH - initial contribution
 *
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

package org.eclipse.mita.platform.xdk110.connectivity

import com.google.inject.Inject
import java.nio.ByteBuffer
import java.util.List
import java.util.regex.Pattern
import org.eclipse.mita.program.EventHandlerDeclaration
import org.eclipse.mita.program.SignalInstance
import org.eclipse.mita.program.SystemResourceSetup
import org.eclipse.mita.program.generator.AbstractSystemResourceGenerator
import org.eclipse.mita.program.generator.CodeFragment
import org.eclipse.mita.program.generator.CodeFragment.IncludePath
import org.eclipse.mita.program.generator.GeneratorUtils
import org.eclipse.mita.program.generator.TypeGenerator
import org.eclipse.mita.program.inferrer.StaticValueInferrer
import org.eclipse.mita.program.model.ModelUtils
import org.yakindu.base.types.inferrer.ITypeSystemInferrer

class SensorServicesGenerator extends AbstractSystemResourceGenerator {
	
	@Inject
	protected ITypeSystemInferrer typeInferrer
	
	@Inject
	protected extension GeneratorUtils
	
	@Inject
	protected TypeGenerator typeGenerator
	
	
	override generateSetup() {
		val baseName = (setup ?: component).baseName;
		
		val deviceName = configuration.getString('deviceName') ?: baseName;
		
		
		codeFragmentProvider.create('''
			Retcode_T retcode = RETCODE_OK;
			BleEventSignal = xSemaphoreCreateBinary();
			if (NULL == BleEventSignal)
			{
				retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_OUT_OF_RESOURCES);
			}
			if (RETCODE_OK == retcode)
			{
			    BleSendCompleteSignal = xSemaphoreCreateBinary();
			    if (NULL == BleSendCompleteSignal)
			    {
			        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_OUT_OF_RESOURCES);
			        vSemaphoreDelete(BleEventSignal);
			    }
			}
			if (RETCODE_OK == retcode)
			{
			    BleSendGuardMutex = xSemaphoreCreateMutex();
			    if (NULL == BleSendGuardMutex)
			    {
			        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_OUT_OF_RESOURCES);
			        vSemaphoreDelete(BleEventSignal);
			        vSemaphoreDelete(BleSendCompleteSignal);
			    }
			}
			if (RETCODE_OK == retcode)
			{
			    retcode =  BlePeripheral_Initialize(«baseName»_OnEvent, «baseName»_ServiceRegistry);
			}
			if (RETCODE_OK == retcode)
			{
			    retcode = BlePeripheral_SetDeviceName((uint8_t*) _BLE_DEVICE_NAME);
			}
	
			return retcode;

		''')
		.addHeader('BCDS_Basics.h', true, IncludePath.VERY_HIGH_PRIORITY)
		.addHeader('BCDS_Retcode.h', true, IncludePath.VERY_HIGH_PRIORITY)
		.addHeader("BCDS_BlePeripheral.h", true, IncludePath.HIGH_PRIORITY)
		.addHeader("BleTypes.h", true)
		.addHeader("attserver.h", true)
		.addHeader("FreeRTOS.h", true, IncludePath.HIGH_PRIORITY)
		.addHeader("task.h", true)
		.addHeader("semphr.h", true)
		.addHeader("stdio.h", true)
		.addHeader("XdkCommonInfo.h", true)
		.addHeader("string.h", true)
		.addHeader("stdlib.h", true)
		.addHeader("BCDS_SensorServices.h", true)
		.setPreamble('''
		#define _BLE_DEVICE_NAME "«deviceName»"
		#define BLE_EVENT_SYNC_TIMEOUT                  UINT32_C(1000)
		static bool BleIsConnected = false;
		/**< Handle for BLE peripheral event signal synchronization */
		static SemaphoreHandle_t BleEventSignal = (SemaphoreHandle_t) NULL;
		/**< Handle for BLE data send complete signal synchronization */
		static SemaphoreHandle_t BleSendCompleteSignal = (SemaphoreHandle_t) NULL;
		/**< Handle for BLE data send Mutex guard */
		static SemaphoreHandle_t BleSendGuardMutex = (SemaphoreHandle_t) NULL;
		/**< BLE peripheral event */
		static BlePeripheral_Event_T BleEvent = BLE_PERIPHERAL_EVENT_MAX;
		/**< BLE send status */
		static Retcode_T BleSendStatus;
		

		«setup.buildServiceCallback(eventHandler)»
		«setup.buildSetupCharacteristic»
		«setup.buildReadWriteCallback(eventHandler)»
		
		static Retcode_T «component.baseName»_SendData(uint8_t* dataToSend, uint8_t dataToSendLen, void * param, uint32_t timeout)
		{
			Retcode_T retcode = RETCODE_OK;
			if (pdTRUE == xSemaphoreTake(BleSendGuardMutex, pdMS_TO_TICKS(BLE_EVENT_SYNC_TIMEOUT)))
			{
				if (BleIsConnected == true)
				{
				 	BleSendStatus = RETCODE_OK;
				    /* This is a dummy take. In case of any callback received
				     * after the previous timeout will be cleared here. */
				     (void) xSemaphoreTake(BleSendCompleteSignal, pdMS_TO_TICKS(0));
						retcode = SensorServices_SendData(dataToSend, dataToSendLen, (Ble_SensorServicesInfo_T *) param);
						if (RETCODE_OK == retcode)
					 	{
							if (pdTRUE != xSemaphoreTake(BleSendCompleteSignal, pdMS_TO_TICKS(timeout)))
							{
								retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_SEND_FAILED);
							}
						}
						else
						{
							 retcode = BleSendStatus;
						}
				}     
				else
				{
				 	retcode = RETCODE(RETCODE_SEVERITY_WARNING, RETCODE_BLE_NOT_CONNECTED);
			    }
						
				if (pdTRUE != xSemaphoreGive(BleSendGuardMutex))
				{
					/* This is fatal since the BleSendGuardMutex must be given as the same thread takes this */
				 	retcode = RETCODE(RETCODE_SEVERITY_FATAL, RETCODE_BLE_SEND_MUTEX_NOT_RELEASED);
				}
			}
			else
			{
				 retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_SEMAPHORE_ERROR);
			}
			return retcode;
		}
		''')
}

	
	private def CodeFragment buildServiceCallback(SystemResourceSetup component, Iterable<EventHandlerDeclaration> declarations) {
		codeFragmentProvider.create('''
		static void «component.baseName»_ServiceCallback(AttServerCallbackParms *serverCallbackParams)
		{
			BCDS_UNUSED(serverCallbackParams);
		}
		
		''')
	}
	
	private def CodeFragment buildReadWriteCallback(SystemResourceSetup component, Iterable<EventHandlerDeclaration> eventHandler) {
		val baseName = component.baseName
		
		codeFragmentProvider.create('''
		static void «baseName»_OnEvent(BlePeripheral_Event_T event, void* data)
		{
		    BCDS_UNUSED(data);
		    BleEvent = event;
		
		    switch (event)
		    {
		    case BLE_PERIPHERAL_STARTED:
		        printf("BleEventCallBack : BLE powered ON successfully \r\n");
		        if (pdTRUE != xSemaphoreGive(BleEventSignal))
		        {
		            /* We would not expect this call to fail because we expect the application thread to wait for this semaphore */
		            Retcode_RaiseError(RETCODE(RETCODE_SEVERITY_WARNING, RETCODE_SEMAPHORE_ERROR));
		        }
		        break;
		    case BLE_PERIPHERAL_SERVICES_REGISTERED:
		        break;
		    case BLE_PERIPHERAL_SLEEP_SUCCEEDED:
		        printf("BleEventCallBack : BLE successfully entered into sleep mode \r\n");
		        break;
		    case BLE_PERIPHERAL_WAKEUP_SUCCEEDED:
		        printf("BleEventCallBack : Device Wake up succeeded \r\n");
		        if (pdTRUE != xSemaphoreGive(BleEventSignal))
		        {
		            /* We would not expect this call to fail because we expect the application thread to wait for this semaphore */
		            Retcode_RaiseError(RETCODE(RETCODE_SEVERITY_WARNING, RETCODE_SEMAPHORE_ERROR));
		        }
		        break;
		    case BLE_PERIPHERAL_CONNECTED:
		        printf("BleEventCallBack : Device connected \r\n");
		        BleIsConnected = true;
		        break;
		    case BLE_PERIPHERAL_DISCONNECTED:
		        printf("BleEventCallBack : Device Disconnected \r\n");
		        BleIsConnected = false;
		        break;
		    case BLE_PERIPHERAL_ERROR:
		        printf("BleEventCallBack : BLE Error Event \r\n");
		        break;
		    default:
		        Retcode_RaiseError(RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_INVALID_EVENT_RECEIVED));
		        break;
		    }
		}
		
		''')
		.addHeader('BCDS_Basics.h', true, IncludePath.VERY_HIGH_PRIORITY)
	}
	
	private def CodeFragment buildSetupCharacteristic(SystemResourceSetup component) {
		val baseName = component.baseName
		
		codeFragmentProvider.create('''
		static Retcode_T «baseName»_ServiceRegistry(void)
		{
			Retcode_T retcode = RETCODE_OK;
			retcode = BleDeviceInformationService_Initialize(UINT32_C(0));
			if (RETCODE_OK == retcode)
			{
				retcode = SensorServices_Init(BleXdkSensorServicesServiceDataRxCB, «baseName»_OnEvent);
			}
			if (RETCODE_OK == retcode)
			{
				retcode = SensorServices_Register();
			}
			if (RETCODE_OK == retcode)
			{
				retcode = BleDeviceInformationService_Register();
			}
			return (retcode);
		}

		''')
	}

	
	override generateEnable() {
		codeFragmentProvider.create('''
		Retcode_T retcode = RETCODE_OK;
		
		/* @todo - BLE in XDK is unstable for wakeup upon bootup.
		 * Added this delay for the same.
		 * This needs to be addressed in the HAL/BSP. */
		vTaskDelay(pdMS_TO_TICKS(1000));
		
		/* This is a dummy take. In case of any callback received
		 * after the previous timeout will be cleared here. */
		(void) xSemaphoreTake(BleEventSignal, pdMS_TO_TICKS(0));
		retcode = BlePeripheral_Start();
		if (RETCODE_OK == retcode)
		{
		    if (pdTRUE != xSemaphoreTake(BleEventSignal, pdMS_TO_TICKS(BLE_EVENT_SYNC_TIMEOUT)))
		    {
		        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_START_FAILED);
		    }
		    else if (BleEvent != BLE_PERIPHERAL_STARTED)
		    {
		        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_START_FAILED);
		    }
		    else
		    {
		        /* Do not disturb retcode */;
		    }
		}
		
		/* This is a dummy take. In case of any callback received
		 * after the previous timeout will be cleared here. */
		(void) xSemaphoreTake(BleEventSignal, pdMS_TO_TICKS(0));
		if (RETCODE_OK == retcode)
		{
		    retcode = BlePeripheral_Wakeup();
		}
		if (RETCODE_OK == retcode)
		{
		    if (pdTRUE != xSemaphoreTake(BleEventSignal, pdMS_TO_TICKS(BLE_EVENT_SYNC_TIMEOUT)))
		    {
		        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_WAKEUP_FAILED);
		    }
		    else if (BleEvent != BLE_PERIPHERAL_WAKEUP_SUCCEEDED)
		    {
		        retcode = RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_BLE_WAKEUP_FAILED);
		    }
		    else
		    {
		        /* Do not disturb retcode */;
		    }
		}
		return retcode;
		''')
	}
	
	override generateSignalInstanceSetter(SignalInstance signalInstance, String resultName) {
		
		val signalName = signalInstance.instanceOf.name;
		if(signalName == "gyro_sensor_service") 
		{
		val gyroDataX = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'x_axis'), [ ]) ?: 0) as Integer;
		val gyroDataY = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'y_axis'), [ ]) ?: 0) as Integer;
		val gyroDataZ = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'z_axis'), [ ]) ?: 0) as Integer;
		
		codeFragmentProvider.create('''
		Retcode_T retcode = RETCODE_OK;
		Ble_SensorServicesInfo_T ServiceInfo;
		int16_t dataX = «gyroDataX»;
		int16_t dataY = «gyroDataY»;
		int16_t dataZ = «gyroDataZ»;
		ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_X;
		ServiceInfo.sensorServicesType = (uint8_t) BLE_SENSOR_GYRO;
		retcode = «component.baseName»_SendData((uint8_t *)&dataX, 4,&ServiceInfo,1000);
		if (RETCODE_OK == retcode)
		{
			ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_Y;
		    retcode = «component.baseName»_SendData((uint8_t *)&dataY, 4, &ServiceInfo, 1000);
		}
		
		if (RETCODE_OK == retcode)
		{
			ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_Z;
		    retcode = «component.baseName»_SendData((uint8_t *)&dataZ, 4, &ServiceInfo, 1000);
		}
		
		return retcode;
		''')
		}
		
		if(signalName == "accelerometer_sensor_service") 
		{
		val accelDataX = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'x_axis'), [ ]) ?: 0) as Integer;
		val accelDataY = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'y_axis'), [ ]) ?: 0) as Integer;
		val accelDataZ = (StaticValueInferrer.infer(ModelUtils.getArgumentValue(signalInstance, 'z_axis'), [ ]) ?: 0) as Integer;
		
		codeFragmentProvider.create('''
		Retcode_T retcode = RETCODE_OK;
		Ble_SensorServicesInfo_T ServiceInfo;
		uint32_t dataX = «accelDataX»;
		uint32_t dataY = «accelDataY»;
		uint32_t dataZ = «accelDataZ»;
		ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_X;
		ServiceInfo.sensorServicesType = (uint8_t) BLE_SENSOR_ACCELEROMETER;
		retcode = «component.baseName»_SendData((uint8_t *)&dataX, 4,&ServiceInfo,1000);
		if (RETCODE_OK == retcode)
		{
			ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_Y;
		    retcode = «component.baseName»_SendData((uint8_t *)&dataY, 4, &ServiceInfo, 1000);
		}
		
		if (RETCODE_OK == retcode)
		{
			ServiceInfo.sensorServicesContent = (uint8_t) SENSOR_AXIS_Z;
		    retcode = «component.baseName»_SendData((uint8_t *)&dataZ, 4, &ServiceInfo, 1000);
		}
		
		return retcode;
		''')
		}

		
	}

	override generateSignalInstanceGetter(SignalInstance signalInstance, String resultName) {
		val baseName = setup.baseName
		
		codeFragmentProvider.create('''
		if(«resultName» == NULL)
		{
			return RETCODE(RETCODE_SEVERITY_ERROR, RETCODE_NULL_POINTER);
		}
		
		memcpy(«resultName», &«baseName»«signalInstance.name.toFirstUpper»Value, sizeof(«resultName»));
		''')
		.addHeader('string.h', true)
	}
	
}