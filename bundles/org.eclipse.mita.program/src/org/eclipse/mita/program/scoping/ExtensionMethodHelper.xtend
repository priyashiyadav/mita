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

package org.eclipse.mita.program.scoping

import org.eclipse.mita.types.NamedProductType
import org.eclipse.mita.types.StructureType
import com.google.common.collect.Lists
import java.util.List
import org.yakindu.base.expressions.expressions.Expression
import org.yakindu.base.types.ComplexType
import org.yakindu.base.types.Operation
import org.yakindu.base.types.Type

class ExtensionMethodHelper {

	def combine(Expression first, List<Expression> others) {
		val args = Lists.newArrayList
		args += first
		args += others
		args
	}
	
	def isExtensionMethodOn(Operation operation, Type callerType) {
		if (callerType instanceof StructureType && (callerType as StructureType).parameters.contains(operation)) {
			// method contained by caller, means it is not an extension method
			return false;
		}
		if (callerType instanceof NamedProductType && (callerType as NamedProductType).parameters.contains(operation)) {
			// method contained by caller, means it is not an extension method
			return false;
		}
		if (callerType instanceof ComplexType && (callerType as ComplexType).allFeatures.contains(operation)) {
			// method contained by caller, means it is not an extension method
			return false;
		}
		return true;
	}
}
