/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include "illusions/bbdou/illusions_bbdou.h"
#include "illusions/bbdou/scriptopcodes_bbdou.h"
#include "illusions/actor.h"
#include "illusions/camera.h"
#include "illusions/dictionary.h"
#include "illusions/input.h"
#include "illusions/resources/scriptresource.h"
#include "illusions/resources/talkresource.h"
#include "illusions/screen.h"
#include "illusions/scriptstack.h"
#include "illusions/sound.h"
#include "illusions/specialcode.h"
#include "illusions/threads/scriptthread.h"

namespace Illusions {

// ScriptOpcodes_BBDOU

ScriptOpcodes_BBDOU::ScriptOpcodes_BBDOU(IllusionsEngine_BBDOU *vm)
	: ScriptOpcodes(vm), _vm(vm) {
	initOpcodes();
}

ScriptOpcodes_BBDOU::~ScriptOpcodes_BBDOU() {
	freeOpcodes();
}

typedef Common::Functor2Mem<ScriptThread*, OpCall&, void, ScriptOpcodes_BBDOU> ScriptOpcodeI;
#define OPCODE(op, func) \
	_opcodes[op] = new ScriptOpcodeI(this, &ScriptOpcodes_BBDOU::func); \
	_opcodeNames[op] = #func;

void ScriptOpcodes_BBDOU::initOpcodes() {
	// First clear everything
	for (uint i = 0; i < 256; ++i)
		_opcodes[i] = 0;
	// Register opcodes
	OPCODE(2, opSuspend);
	OPCODE(3, opYield);
	OPCODE(4, opTerminate);
	OPCODE(5, opJump);
	OPCODE(6, opStartScriptThread);
	OPCODE(8, opStartTempScriptThread);
	OPCODE(9, opStartTimerThread);
	OPCODE(12, opNotifyThreadId);
	OPCODE(14, opSetThreadSceneId);
	OPCODE(15, opEndTalkThreads);
	OPCODE(16, opLoadResource);
	OPCODE(17, opUnloadResource);
	OPCODE(20, opEnterScene);
	OPCODE(25, opChangeScene);
	OPCODE(26, opStartModalScene);
	OPCODE(27, opExitModalScene);
	OPCODE(30, opEnterCloseUpScene);
	OPCODE(31, opExitCloseUpScene);
	OPCODE(32, opPanCenterObject);
	OPCODE(34, opPanToObject);
	OPCODE(35, opPanToNamedPoint);
	OPCODE(36, opPanToPoint);
	OPCODE(37, opPanStop);
	OPCODE(39, opSetDisplay);
	OPCODE(42, opIncBlockCounter);
	OPCODE(43, opClearBlockCounter);
	OPCODE(45, opSetProperty);
	OPCODE(46, opPlaceActor);
	OPCODE(47, opFaceActor);
	OPCODE(48, opFaceActorToObject);	
	OPCODE(49, opStartSequenceActor);
	OPCODE(51, opStartMoveActor);
	OPCODE(53, opSetActorToNamedPoint);
	OPCODE(56, opStartTalkThread);
	OPCODE(57, opAppearActor);
	OPCODE(58, opDisappearActor);
	OPCODE(60, opActivateObject);
	OPCODE(61, opDeactivateObject);
	OPCODE(62, opSetDefaultSequence);
	OPCODE(63, opSetSelectSfx);
	OPCODE(64, opSetMoveSfx);
	OPCODE(65, opSetDenySfx);
	OPCODE(66, opSetAdjustUpSfx);
	OPCODE(67, opSetAdjustDnSfx);
	OPCODE(71, opStartSound);
	OPCODE(74, opStopSound);
	OPCODE(75, opStartMusic);
	OPCODE(76, opStopMusic);
	OPCODE(78, opStackPushRandom);
	OPCODE(79, opIfLte);
	OPCODE(80, opAddMenuChoice);
	OPCODE(81, opDisplayMenu);
	OPCODE(82, opSwitchMenuChoice);
	OPCODE(84, opResetGame);
	OPCODE(87, opDeactivateButton);
	OPCODE(88, opActivateButton);
	OPCODE(103, opJumpIf);
	OPCODE(104, opIsPrevSceneId);
	OPCODE(105, opIsCurrentSceneId);
	OPCODE(106, opIsActiveSceneId);
	OPCODE(107, opNot);
	OPCODE(108, opAnd);
	OPCODE(109, opOr);
	OPCODE(110, opGetProperty);
	OPCODE(111, opCompareBlockCounter);
	OPCODE(126, opDebug126);
	OPCODE(144, opPlayVideo);
	OPCODE(146, opStackPop);
	OPCODE(147, opStackDup);
	OPCODE(148, opLoadSpecialCodeModule);
	OPCODE(150, opRunSpecialCode);
	OPCODE(160, opStopActor);
	OPCODE(161, opSetActorUsePan);
	OPCODE(168, opStartAbortableThread);
	OPCODE(169, opKillThread);
	OPCODE(175, opSetSceneIdThreadId);
	OPCODE(176, opStackPush0);
	OPCODE(177, opSetFontId);
	OPCODE(178, opAddMenuKey);
	OPCODE(179, opChangeSceneAll);
}

#undef OPCODE

void ScriptOpcodes_BBDOU::freeOpcodes() {
	for (uint i = 0; i < 256; ++i)
		delete _opcodes[i];
}

// Opcodes

void ScriptOpcodes_BBDOU::opSuspend(ScriptThread *scriptThread, OpCall &opCall) {
	opCall._result = kTSSuspend;
}

void ScriptOpcodes_BBDOU::opYield(ScriptThread *scriptThread, OpCall &opCall) {
	opCall._result = kTSYield;
}

void ScriptOpcodes_BBDOU::opTerminate(ScriptThread *scriptThread, OpCall &opCall) {
	opCall._result = kTSTerminate;
}

void ScriptOpcodes_BBDOU::opJump(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(jumpOffs);
	opCall._deltaOfs += jumpOffs;
}

void ScriptOpcodes_BBDOU::opStartScriptThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(threadId);
	_vm->startScriptThread(threadId, opCall._threadId,
		scriptThread->_value8, scriptThread->_valueC, scriptThread->_value10);
}

void ScriptOpcodes_BBDOU::opStartTempScriptThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(codeOffs);
	_vm->startTempScriptThread(opCall._code + codeOffs,
		opCall._threadId, scriptThread->_value8, scriptThread->_valueC, scriptThread->_value10);
}

void ScriptOpcodes_BBDOU::opStartTimerThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(isAbortable);
	ARG_INT16(duration);
	ARG_INT16(maxDuration);
	if (maxDuration)
		duration += _vm->getRandom(maxDuration);
		
duration = 1;//DEBUG Speeds up things		
		
	if (isAbortable)
		_vm->startAbortableTimerThread(duration, opCall._threadId);
	else
		_vm->startTimerThread(duration, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opNotifyThreadId(ScriptThread *scriptThread, OpCall &opCall) {
	Thread *thread = _vm->_threads->findThread(opCall._callerThreadId);
	if (!(thread->_notifyFlags & 1))
		_vm->notifyThreadId(thread->_callingThreadId);
}

void ScriptOpcodes_BBDOU::opSetThreadSceneId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	_vm->_threads->setThreadSceneId(opCall._callerThreadId, sceneId);
}

void ScriptOpcodes_BBDOU::opEndTalkThreads(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_threads->endTalkThreads();
}

void ScriptOpcodes_BBDOU::opLoadResource(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(resourceId);
	// NOTE Skipped checking for stalled resources
	uint32 sceneId = _vm->getCurrentScene();
	_vm->_resSys->loadResource(resourceId, sceneId, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opUnloadResource(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(resourceId);
	// NOTE Skipped checking for stalled resources
	_vm->_resSys->unloadResourceById(resourceId);
}

void ScriptOpcodes_BBDOU::opEnterScene(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	uint scenesCount = _vm->_activeScenes.getActiveScenesCount();
	if (scenesCount > 0) {
		uint32 currSceneId;
		_vm->_activeScenes.getActiveSceneInfo(scenesCount, &currSceneId, 0);
		// TODO krnfileDump(currSceneId);
	}
	if (!_vm->enterScene(sceneId, opCall._callerThreadId))
		opCall._result = kTSTerminate;
}

//DEBUG Scenes
//uint32 dsceneId = 0x00010031, dthreadId = 0x00020036;//MAP
//uint32 dsceneId = 0x00010028, dthreadId = 0x000202A1;
//uint32 dsceneId = 0x00010007, dthreadId = 0x0002000C;//Auditorium
//uint32 dsceneId = 0x0001000B, dthreadId = 0x00020010;
//uint32 dsceneId = 0x00010013, dthreadId = 0x00020018;//Therapist
//uint32 dsceneId = 0x00010016, dthreadId = 0x0002001B;//Dorms ext
//uint32 dsceneId = 0x00010017, dthreadId = 0x0002001C;//Dorms int
//uint32 dsceneId = 0x0001000D, dthreadId = 0x00020012;//Food minigame
//uint32 dsceneId = 0x00010067, dthreadId = 0x0002022A;
//uint32 dsceneId = 0x0001000C, dthreadId = 0x00020011;//Cafeteria
//uint32 dsceneId = 0x0001000B, dthreadId = 0x00020010;
uint32 dsceneId = 0x0001001A, dthreadId = 0x0002001F;

void ScriptOpcodes_BBDOU::opChangeScene(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	ARG_UINT32(threadId);

	if (dsceneId) {
		sceneId = dsceneId;
		threadId = dthreadId;
		dsceneId = 0;
	}
	
	// NOTE Skipped checking for stalled resources
	_vm->_input->discardAllEvents();
	_vm->_prevSceneId = _vm->getCurrentScene();
	_vm->exitScene(opCall._callerThreadId);
	_vm->enterScene(sceneId, opCall._callerThreadId);
	// TODO _vm->_gameStates->writeStates(_vm->_prevSceneId, sceneId, threadId);
	_vm->startAnonScriptThread(threadId, 0,
		scriptThread->_value8, scriptThread->_valueC, scriptThread->_value10);
}

void ScriptOpcodes_BBDOU::opStartModalScene(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	ARG_UINT32(threadId);
	// NOTE Skipped checking for stalled resources
	_vm->_input->discardAllEvents();
	_vm->enterPause(opCall._callerThreadId);
	_vm->_talkItems->pauseBySceneId(_vm->getCurrentScene());
	_vm->enterScene(sceneId, opCall._callerThreadId);
	_vm->startScriptThread(threadId, 0,
		scriptThread->_value8, scriptThread->_valueC, scriptThread->_value10);
	opCall._result = kTSSuspend;
}

void ScriptOpcodes_BBDOU::opExitModalScene(ScriptThread *scriptThread, OpCall &opCall) {
	// NOTE Skipped checking for stalled resources
	_vm->_input->discardAllEvents();
	_vm->exitScene(opCall._callerThreadId);
	_vm->leavePause(opCall._callerThreadId);
	_vm->_talkItems->unpauseBySceneId(_vm->getCurrentScene());
}

void ScriptOpcodes_BBDOU::opEnterCloseUpScene(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	// NOTE Skipped checking for stalled resources
	_vm->_input->discardAllEvents();
	_vm->enterPause(opCall._callerThreadId);
	_vm->enterScene(sceneId, opCall._callerThreadId);
}

void ScriptOpcodes_BBDOU::opExitCloseUpScene(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->exitScene(opCall._callerThreadId);
	_vm->leavePause(opCall._callerThreadId);
	opCall._result = kTSYield;
}

void ScriptOpcodes_BBDOU::opPanCenterObject(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(speed);	
	ARG_UINT32(objectId);
	_vm->_camera->panCenterObject(objectId, speed);
}

void ScriptOpcodes_BBDOU::opPanToObject(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(speed);	
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	Common::Point pos = control->getActorPosition();
	_vm->_camera->panToPoint(pos, speed, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opPanToNamedPoint(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(speed);	
	ARG_UINT32(namedPointId);
	Common::Point pos = _vm->getNamedPointPosition(namedPointId);
	_vm->_camera->panToPoint(pos, speed, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opPanToPoint(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(speed);	
	ARG_INT16(x);	
	ARG_INT16(y);	
	_vm->_camera->panToPoint(Common::Point(x, y), speed, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opPanStop(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_camera->stopPan();
}

void ScriptOpcodes_BBDOU::opSetDisplay(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(flag);
	_vm->_screen->setDisplayOn(flag != 0);
}

void ScriptOpcodes_BBDOU::opIncBlockCounter(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(index);	
	byte value = _vm->_scriptResource->_blockCounters.get(index) + 1;
	if (value <= 63)
		_vm->_scriptResource->_blockCounters.set(index, value);
}

void ScriptOpcodes_BBDOU::opClearBlockCounter(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(index);
	_vm->_scriptResource->_blockCounters.set(index, 0);
}

void ScriptOpcodes_BBDOU::opSetProperty(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(value);	
	ARG_UINT32(propertyId);	
	_vm->_scriptResource->_properties.set(propertyId, value != 0);
}

void ScriptOpcodes_BBDOU::opPlaceActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(actorTypeId);
	ARG_UINT32(sequenceId);
	ARG_UINT32(namedPointId);
	Common::Point pos = _vm->getNamedPointPosition(namedPointId);
	_vm->_controls->placeActor(actorTypeId, pos, sequenceId, objectId, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opFaceActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(facing);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->faceActor(facing);
}

void ScriptOpcodes_BBDOU::opFaceActorToObject(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId1);
	ARG_UINT32(objectId2);
	Control *control1 = _vm->_dict->getObjectControl(objectId1);
	Control *control2 = _vm->_dict->getObjectControl(objectId2);
	Common::Point pos1 = control1->getActorPosition();
	Common::Point pos2 = control2->getActorPosition();
	uint facing;
	if (_vm->calcPointDirection(pos1, pos2, facing))
		control1->faceActor(facing);
}

void ScriptOpcodes_BBDOU::opStartSequenceActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(sequenceId);
	// NOTE Skipped checking for stalled sequence, not sure if needed
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->startSequenceActor(sequenceId, 2, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opStartMoveActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(sequenceId);
	ARG_UINT32(namedPointId);
	// NOTE Skipped checking for stalled sequence, not sure if needed
	Control *control = _vm->_dict->getObjectControl(objectId);
	Common::Point pos = _vm->getNamedPointPosition(namedPointId);
	control->startMoveActor(sequenceId, pos, opCall._callerThreadId, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opSetActorToNamedPoint(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(namedPointId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	Common::Point pos = _vm->getNamedPointPosition(namedPointId);
	control->stopActor();
	control->setActorPosition(pos);
}

void ScriptOpcodes_BBDOU::opStartTalkThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(duration);	
	ARG_UINT32(objectId);
	ARG_UINT32(talkId);
	ARG_UINT32(sequenceId1);
	ARG_UINT32(sequenceId2);
	ARG_UINT32(namedPointId);
	_vm->startTalkThread(duration, objectId, talkId, sequenceId1, sequenceId2, namedPointId, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opAppearActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	if (!control) {
		Common::Point pos = _vm->getNamedPointPosition(0x70023);
		_vm->_controls->placeActor(0x50001, pos, 0x60001, objectId, 0);
		control = _vm->_dict->getObjectControl(objectId);
		control->startSequenceActor(0x60001, 2, 0);
	}
	control->appearActor();
}

void ScriptOpcodes_BBDOU::opDisappearActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->disappearActor();
}

void ScriptOpcodes_BBDOU::opActivateObject(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	if (control)
		control->activateObject();
}

void ScriptOpcodes_BBDOU::opDeactivateObject(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->deactivateObject();
}

void ScriptOpcodes_BBDOU::opSetDefaultSequence(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(defaultSequenceId);
	ARG_UINT32(sequenceId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->_actor->_defaultSequences.set(sequenceId, defaultSequenceId);
}

void ScriptOpcodes_BBDOU::opSetSelectSfx(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	// TODO _vm->setSelectSfx(soundEffectId);
}

void ScriptOpcodes_BBDOU::opSetMoveSfx(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	// TODO _vm->setMoveSfx(soundEffectId);
}

void ScriptOpcodes_BBDOU::opSetDenySfx(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	// TODO _vm->setDenySfx(soundEffectId);
}

void ScriptOpcodes_BBDOU::opSetAdjustUpSfx(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	// TODO _vm->setAdjustUpSfx(soundEffectId);
}

void ScriptOpcodes_BBDOU::opSetAdjustDnSfx(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	// TODO _vm->setAdjustDnSfx(soundEffectId);
}

void ScriptOpcodes_BBDOU::opStartSound(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_INT16(volume);
	ARG_INT16(pan);
	ARG_UINT32(soundEffectId);
	_vm->_soundMan->playSound(soundEffectId, volume, pan);
}
void ScriptOpcodes_BBDOU::opStopSound(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(soundEffectId);
	_vm->_soundMan->stopSound(soundEffectId);
}

void ScriptOpcodes_BBDOU::opStartMusic(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_INT16(volume);
	ARG_INT16(pan);
	ARG_UINT32(musicId);
	ARG_UINT32(type);
	_vm->_soundMan->playMusic(musicId, type, volume, pan, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opStopMusic(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_soundMan->stopMusic();
}

void ScriptOpcodes_BBDOU::opStackPushRandom(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(maxValue);
	_vm->_stack->push(_vm->getRandom(maxValue) + 1);
}

void ScriptOpcodes_BBDOU::opIfLte(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_INT16(rvalue);
	ARG_INT16(elseJumpOffs);
	int16 lvalue = _vm->_stack->pop();
	if (!(lvalue <= rvalue))
		opCall._deltaOfs += elseJumpOffs;
}

void ScriptOpcodes_BBDOU::opAddMenuChoice(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_INT16(jumpOffs);
	ARG_INT16(endMarker);
	_vm->_stack->push(endMarker);
	_vm->_stack->push(jumpOffs);
}

void ScriptOpcodes_BBDOU::opDisplayMenu(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(unk1);
	ARG_UINT32(menuId);
	ARG_UINT32(unk2);
	// TODO _vm->_shellMgr->displayMenu(_vm->_stack->topPtr(), &_vm->_menuChoiceOfs, menuId, unk1, unk2, opCall._callerThreadId);
	// Remove menu choices from the stack
	do {
		_vm->_stack->pop();
	} while (_vm->_stack->pop() == 0);

	//DEBUG Resume calling thread, later done by the video player
	_vm->notifyThreadId(opCall._callerThreadId);

}

void ScriptOpcodes_BBDOU::opSwitchMenuChoice(ScriptThread *scriptThread, OpCall &opCall) {
_vm->_menuChoiceOfs = 88; // DEBUG Chose "Start game"

	opCall._deltaOfs += _vm->_menuChoiceOfs;
}

void ScriptOpcodes_BBDOU::opResetGame(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_threads->terminateThreads(opCall._callerThreadId);
	_vm->reset();
	_vm->_input->activateButton(0xFFFF);
	// TODO _vm->stopMusic();
	// TODO _vm->_gameStates->clear();
}

void ScriptOpcodes_BBDOU::opDeactivateButton(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(button)
	_vm->_input->deactivateButton(button);
}

void ScriptOpcodes_BBDOU::opActivateButton(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(button)
	_vm->_input->activateButton(button);
}

void ScriptOpcodes_BBDOU::opJumpIf(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(jumpOffs);
	int16 value = _vm->_stack->pop();
	if (value == 0)
		opCall._deltaOfs += jumpOffs;
}

void ScriptOpcodes_BBDOU::opIsPrevSceneId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	_vm->_stack->push(_vm->_prevSceneId == sceneId ? 1 : 0);
}

void ScriptOpcodes_BBDOU::opIsCurrentSceneId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	_vm->_stack->push(_vm->getCurrentScene() == sceneId ? 1 : 0);
}

void ScriptOpcodes_BBDOU::opIsActiveSceneId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	_vm->_stack->push(_vm->_activeScenes.isSceneActive(sceneId) ? 1 : 0);
}

void ScriptOpcodes_BBDOU::opNot(ScriptThread *scriptThread, OpCall &opCall) {
	int16 value = _vm->_stack->pop();
	_vm->_stack->push(value != 0 ? 0 : 1);
}

void ScriptOpcodes_BBDOU::opAnd(ScriptThread *scriptThread, OpCall &opCall) {
	int16 value1 = _vm->_stack->pop();
	int16 value2 = _vm->_stack->pop();
	_vm->_stack->push(value1 & value2);
}

void ScriptOpcodes_BBDOU::opOr(ScriptThread *scriptThread, OpCall &opCall) {
	int16 value1 = _vm->_stack->pop();
	int16 value2 = _vm->_stack->pop();
	_vm->_stack->push(value1 | value2);
}

void ScriptOpcodes_BBDOU::opGetProperty(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(propertyId)
	bool value = _vm->_scriptResource->_properties.get(propertyId);
	_vm->_stack->push(value ? 1 : 0);
}

void ScriptOpcodes_BBDOU::opCompareBlockCounter(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(index);	
	ARG_INT16(compareOp);	
	ARG_INT16(rvalue);
	int16 lvalue = _vm->_scriptResource->_blockCounters.get(index);
	bool compareResult = false;
	switch (compareOp) {
	case 1:
		compareResult = lvalue == rvalue;
		break;
	case 2:
		compareResult = lvalue != rvalue;
		break;
	case 3:
		compareResult = lvalue < rvalue;
		break;
	case 4:
		compareResult = lvalue > rvalue;
		break;
	case 5:
		compareResult = lvalue >= rvalue;
		break;
	case 6:
		compareResult = lvalue <= rvalue;
		break;
	}
	_vm->_stack->push(compareResult ? 1 : 0);
}

void ScriptOpcodes_BBDOU::opDebug126(ScriptThread *scriptThread, OpCall &opCall) {
	// NOTE Prints some debug text
	debug(1, "[DBG] %s", (char*)opCall._code);
}

void ScriptOpcodes_BBDOU::opPlayVideo(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	ARG_UINT32(videoId);
	ARG_UINT32(priority);
	// TODO _vm->playVideo(videoId, objectId, value, opCall._threadId);
	
	//DEBUG Resume calling thread, later done by the video player
	_vm->notifyThreadId(opCall._callerThreadId);
	
}

void ScriptOpcodes_BBDOU::opStackPop(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_stack->pop(); 
}

void ScriptOpcodes_BBDOU::opStackDup(ScriptThread *scriptThread, OpCall &opCall) {
	int16 value = _vm->_stack->peek();
	_vm->_stack->push(value); 
}

void ScriptOpcodes_BBDOU::opLoadSpecialCodeModule(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(specialCodeModuleId);
	_vm->_resSys->loadResource(specialCodeModuleId, 0, 0);
}

void ScriptOpcodes_BBDOU::opRunSpecialCode(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(specialCodeId);
	_vm->_specialCode->run(specialCodeId, opCall);
}

void ScriptOpcodes_BBDOU::opStopActor(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->stopActor();
}

void ScriptOpcodes_BBDOU::opSetActorUsePan(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_INT16(usePan)
	ARG_UINT32(objectId);
	Control *control = _vm->_dict->getObjectControl(objectId);
	control->setActorUsePan(usePan);
}

void ScriptOpcodes_BBDOU::opStartAbortableThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_INT16(codeOffs);
	ARG_INT16(skipOffs);
	_vm->startAbortableThread(opCall._code + codeOffs,
		opCall._code + skipOffs, opCall._threadId);
}

void ScriptOpcodes_BBDOU::opKillThread(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(threadId);
	_vm->_threads->killThread(threadId);
}

void ScriptOpcodes_BBDOU::opSetSceneIdThreadId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	ARG_UINT32(threadId);
	_vm->setSceneIdThreadId(sceneId, threadId);
}

void ScriptOpcodes_BBDOU::opStackPush0(ScriptThread *scriptThread, OpCall &opCall) {
	_vm->_stack->push(0);
}

void ScriptOpcodes_BBDOU::opSetFontId(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(fontId);
	_vm->setCurrFontId(fontId);
}

void ScriptOpcodes_BBDOU::opAddMenuKey(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(key);
	ARG_UINT32(threadId);
	// TODO _vm->addMenuKey(key, threadId);
}

void ScriptOpcodes_BBDOU::opChangeSceneAll(ScriptThread *scriptThread, OpCall &opCall) {
	ARG_SKIP(2);
	ARG_UINT32(sceneId);
	ARG_UINT32(threadId);
	// NOTE Skipped checking for stalled resources
	_vm->_input->discardAllEvents();
	_vm->_prevSceneId = _vm->getCurrentScene();
	_vm->dumpActiveScenes(_vm->_globalSceneId, opCall._callerThreadId);
	_vm->enterScene(sceneId, opCall._callerThreadId);
	// TODO _vm->_gameStates->writeStates(_vm->_prevSceneId, sceneId, threadId);
	_vm->startAnonScriptThread(threadId, 0,
		scriptThread->_value8, scriptThread->_valueC, scriptThread->_value10);
}

} // End of namespace Illusions