AzeriteEmpoweredItemTierMixin = {};

AzeriteEmpoweredItemTierMixin.ANIM_STATE_NONE = nil;
AzeriteEmpoweredItemTierMixin.ANIM_STATE_START_HOLD = 1;
AzeriteEmpoweredItemTierMixin.ANIM_STATE_ROTATING = 2;
AzeriteEmpoweredItemTierMixin.ANIM_STATE_END_HOLD = 3;

AzeriteEmpoweredItemTierMixin.BACKGROUND_GLOW_STATE_NONE = nil;
AzeriteEmpoweredItemTierMixin.BACKGROUND_GLOW_STATE_SELECTION_ACTIVE = 1;
AzeriteEmpoweredItemTierMixin.BACKGROUND_GLOW_STATE_SELECTED = 2;

local INNER_GEAR_ANIM_RATE = .25; -- percent

function AzeriteEmpoweredItemTierMixin:OnLoad()
	local startingSound = nil;
	local loopingSound = SOUNDKIT.UI_80_AZERITEARMOR_ROTATION_LOOP;
	local endingSound = SOUNDKIT.UI_80_AZERITEARMOR_ROTATIONENDCLICKS;

	local loopStartDelay = .25;
	local loopEndDelay = 0;
	local loopFadeTime = 500; -- ms
	self.loopingSoundEmitter = CreateLoopingSoundEffectEmitter(startingSound, loopingSound, endingSound, loopStartDelay, loopEndDelay, loopFadeTime);
end

function AzeriteEmpoweredItemTierMixin:Reset()
	self.animState = self.ANIM_STATE_NONE;
	self.animContextData = nil;

	self.owningFrame = nil;
	self.azeritePowerButtons = {};
	self.selectedPowerID = nil;
	self.meetsPowerLevelRequirement = false;
	self.prereqTier = nil;
	self.tierRingGlow = nil;
	self.glowState = nil;
	self.tierPlug = nil;
	self.tierPlugBackground = nil;
	self.tierInfo = nil;
	self.rankFrame = nil;
	self.tierSelectedLights = nil;
	self.tierSlot = nil;

	self.transformNode = nil;
	self.animatedGearNode = nil;

	self.loopingSoundEmitter:CancelLoopingSound();
end

function AzeriteEmpoweredItemTierMixin:SetOwner(owningFrame, azeriteItemDataSource)
	self.owningFrame = owningFrame;
	self.azeriteItemDataSource = azeriteItemDataSource;
end

function AzeriteEmpoweredItemTierMixin:SetTierInfo(tierIndex, numTiers, tierInfo, prereqTier)
	self.tierIndex = tierIndex;
	self.tierOffset = AZERITE_EMPOWERED_ITEM_MAX_TIERS - numTiers;
	self.tierInfo = tierInfo;
	self.prereqTier = prereqTier;
	self.isFinalTier = tierIndex == numTiers;
end

function AzeriteEmpoweredItemTierMixin:SetVisuals(tierSlot, rankFrame, tierPlug, rootTransformNode)
	self.tierSlot = tierSlot;
	self.tierPlug = tierPlug;

	self.rankFrame = rankFrame;
	if self.rankFrame then
		self.rankFrame:Show();
		
		self.tierSelectedLights = rankFrame.RingLights;
		self.tierRingGlow = rankFrame.RingBgGlow;
		self.tierPlugBackground = rankFrame.PlugBg;

		self.animatedGearNode = rankFrame.Gear.transformNode;

		self.transformNode = rankFrame.RingBg.transformNode;
	else
		self.transformNode = rootTransformNode;
	end
end

function AzeriteEmpoweredItemTierMixin:SetupPlugs()
	if self.tierPlug or self.tierPlugBackground or self.tierSlot then
		if self.tierPlugBackground then
			self.tierPlugBackground:Show();
		end
		if self.tierSlot then
			self.tierSlot:Show();
		end

		local offset = AzeriteLayoutInfo.CalculatePlugOffset(self:GetTierIndex() + self.tierOffset);

		local function ApplyOffset(texture, offset)
			local scale = texture:GetScale();
			texture:SetPoint("CENTER", texture:GetParent(), "CENTER", offset.x / scale, offset.y / scale);
		end

		if self.tierPlug then
			ApplyOffset(self.tierPlug, offset);
		end
		if self.tierPlugBackground then
			ApplyOffset(self.tierPlugBackground, offset);
		end
		if self.tierSlot then
			ApplyOffset(self.tierSlot, offset);
		end
	end
end

function AzeriteEmpoweredItemTierMixin:CreatePowers(powerPool)
	local numPowers = #self.tierInfo.azeritePowerIDs;
	for powerIndex, azeritePowerID in ipairs(self.tierInfo.azeritePowerIDs) do
		local localNodePosition, angleRads = AzeriteLayoutInfo.CalculatePowerOffset(powerIndex, numPowers, self:GetTierIndex() + self.tierOffset);
		local azeritePowerButton = powerPool:Acquire(self.transformNode, localNodePosition);

		azeritePowerButton:Setup(self, self.azeriteItemDataSource, azeritePowerID, -angleRads);
		table.insert(self.azeritePowerButtons, azeritePowerButton);

		azeritePowerButton:Show();
	end

	self:SetupPlugs();
end

function AzeriteEmpoweredItemTierMixin:Update(azeriteItemPowerLevel)
	self.azeriteItemPowerLevel = azeriteItemPowerLevel;
	self.meetsPowerLevelRequirement = azeriteItemPowerLevel >= self.tierInfo.unlockLevel;
	self.selectedPowerID = nil;

	if self:IsAnimating() then
		return;
	end

	self:UpdatePowerStates();

	if self.tierSlot then
		self.tierSlot:SetPowerLevelInfo(self.azeriteItemPowerLevel, self.tierInfo.unlockLevel, self:HasAnySelected(), self:IsSelectionActive(), self.azeriteItemDataSource:IsPreviewSource(), self:IsFinalTier());
	end

	self:SnapToSelection();
end

function AzeriteEmpoweredItemTierMixin:UpdatePowerStates()
	for powerIndex, azeritePowerButton in ipairs(self.azeritePowerButtons) do
		azeritePowerButton:Update();

		if azeritePowerButton:IsSelected() then
			self.selectedPowerID = azeritePowerButton:GetAzeritePowerID();
		end
	end

	local isSelectionActive = not self:IsAnimating() and self:IsSelectionActive();
	local specID = GetSpecializationInfo(GetSpecialization())
	for powerIndex, azeritePowerButton in ipairs(self.azeritePowerButtons) do
		local isSpecAllowed = C_AzeriteEmpoweredItem.IsPowerAvailableForSpec(azeritePowerButton:GetAzeritePowerID(), specID);
		azeritePowerButton:SetCanBeSelectedDetails(isSelectionActive, self.meetsPowerLevelRequirement, self.tierInfo.unlockLevel, isSpecAllowed, self:HasAnySelected());
	end

	if not self:IsAnimating() then
		self:TransitionBackgroundGlow(isSelectionActive and self.BACKGROUND_GLOW_STATE_SELECTION_ACTIVE or self.BACKGROUND_GLOW_STATE_NONE);
	end

	if self.tierPlug then
		self.tierPlug:SetShown(not self:IsAnimating() and not self:HasAnySelected() and not isSelectionActive);
	end
end

function AzeriteEmpoweredItemTierMixin:TransitionBackgroundGlow(glowState)
	if self.rankFrame and self.glowState ~= glowState then
		if glowState == self.BACKGROUND_GLOW_STATE_NONE then
			self.rankFrame.SelectionActiveFadeAnim:SetScript("OnFinished", nil);
			self.rankFrame.SelectionActiveFadeAnim.Alpha:SetFromAlpha(self.tierRingGlow:GetAlpha());
			self.rankFrame.SelectionActiveFadeAnim.Alpha:SetToAlpha(0.0);
			self.rankFrame.SelectionActiveFadeAnim:Stop();
			self.rankFrame.SelectionActiveLoopAnim:Stop();
			self.rankFrame.SelectedGlowAnim:Stop();

			self.rankFrame.SelectionActiveFadeAnim:Play();
		elseif glowState == self.BACKGROUND_GLOW_STATE_SELECTION_ACTIVE then
			self.rankFrame.SelectedGlowAnim:Stop();
			self.rankFrame.SelectionActiveFadeAnim:Stop();

			if not self.rankFrame.SelectionActiveLoopAnim:IsPlaying() then
				self.rankFrame.SelectionActiveFadeAnim.Alpha:SetFromAlpha(self.tierRingGlow:GetAlpha());
				self.rankFrame.SelectionActiveFadeAnim.Alpha:SetToAlpha(0.5);

				self.rankFrame.SelectionActiveFadeAnim:SetScript("OnFinished", function()
					self.rankFrame.SelectionActiveFadeAnim:SetScript("OnFinished", nil);

					self.rankFrame.SelectionActiveLoopAnim:Play();
				end);
				self.rankFrame.SelectionActiveFadeAnim:Play();
			end
		elseif glowState == self.BACKGROUND_GLOW_STATE_SELECTED then
			self.rankFrame.SelectionActiveFadeAnim:SetScript("OnFinished", nil);

			self.rankFrame.SelectedGlowAnim.Alpha:SetFromAlpha(self.tierRingGlow:GetAlpha());
			self.rankFrame.SelectionActiveLoopAnim:Stop();

			self.rankFrame.SelectionActiveFadeAnim:Stop();

			self.rankFrame.SelectedGlowAnim:Play();
		end

		self.glowState = glowState;
	end
end

local function LockInEase(percent)
	if percent < .5 then
		return ((percent * 2) ^ 2) / 2;
	end
	return 1 - (((1 - percent) * 2) ^ 2) / 2;
end

function AzeriteEmpoweredItemTierMixin:TryShaking(elapsed, magnitude, frequency)
	if self:IsFinalTier() then
		return;
	end

	self.animContextData.elapsed = (self.animContextData.elapsed or 0) + elapsed;
	if self.animContextData.elapsed > frequency then
		self.transformNode:SetLocalPosition(CreateVector2D(Lerp(-magnitude, magnitude, math.random()), Lerp(-magnitude, magnitude, math.random())));
		self.animContextData.elapsed = self.animContextData.elapsed - frequency;
	end
end

local function GetTotalProgressPercent(animState, localPercent)
	return ClampedPercentageBetween(animState + localPercent, AzeriteEmpoweredItemTierMixin.ANIM_STATE_START_HOLD, AzeriteEmpoweredItemTierMixin.ANIM_STATE_END_HOLD + 1);
end

function AzeriteEmpoweredItemTierMixin:PerformAnimations(elapsed)
	if self:IsAnimating() then
		local animContextData = self.animContextData[self.animState];
		local now = GetTime();

		if self.animState == self.ANIM_STATE_START_HOLD then
			local percent = ClampedPercentageBetween(now, animContextData.startTime, animContextData.endTime);
			self.owningFrame:OnTierAnimationProgress(self, GetTotalProgressPercent(self.animState, percent));

			self:TryShaking(elapsed, percent * .8, .05);
			if now >= animContextData.endTime then
				self:SetAnimState(self.ANIM_STATE_ROTATING);
			end
		elseif self.animState == self.ANIM_STATE_ROTATING then
			local startTime = animContextData.startTime;
			local durationSec = animContextData.durationSec;
			local endTime = startTime + durationSec;

			local percent = ClampedPercentageBetween(now, startTime, endTime);
			self.owningFrame:OnTierAnimationProgress(self, GetTotalProgressPercent(self.animState, percent));

			if self:IsFinalTier() then
				if percent > .5 and not animContextData.hasPlayedLockInEffect then
					animContextData.hasPlayedLockInEffect = true;
					PlaySound(SOUNDKIT.UI_80_AZERITEARMOR_ROTATIONENDS);
					self:PlayLockedInEffect();
				end

				if percent == 1.0 then
					self:SetAnimState(self.ANIM_STATE_END_HOLD);
				end
			else
				local startAngle = animContextData.startAngle;
				local angleDelta = animContextData.angleDelta;
				local targetAngle = startAngle + angleDelta;

				local newRotation = Lerp(startAngle, targetAngle, LockInEase(percent));

				local LERP_AMOUNT_PER_NORMALIZED_FRAME = .2;
				local smoothedRotation = FrameDeltaLerp(self.transformNode:GetLocalRotation(), newRotation, LERP_AMOUNT_PER_NORMALIZED_FRAME);

				if percent > .85 and not animContextData.hasPlayedEndingClickSound then
					animContextData.hasPlayedEndingClickSound = true;
					self.loopingSoundEmitter:FinishLoopingSound();
				end

				if percent > .95 and not animContextData.hasPlayedLockInEffect then
					animContextData.hasPlayedLockInEffect = true;
					PlaySound(SOUNDKIT.UI_80_AZERITEARMOR_ROTATIONENDS);
					self:PlayLockedInEffect();
					self.animContextData.azeritePowerButton:PlaySelectedAnimation();
				end

				local CLOSE_ENOUGH_ANGLE_DIFF = math.pi * .0001;
				if percent == 1.0 and math.abs(newRotation - smoothedRotation) < CLOSE_ENOUGH_ANGLE_DIFF then
					self:SetNodeRotations(newRotation);
					self.transformNode:SetLocalPosition(CreateVector2D(0, 0));
					self:SetAnimState(self.ANIM_STATE_END_HOLD);
				else
					self:SetNodeRotations(smoothedRotation);
				end
			end
		elseif self.animState == self.ANIM_STATE_END_HOLD then
			local percent = ClampedPercentageBetween(now, animContextData.startTime, animContextData.endTime);
			self.owningFrame:OnTierAnimationProgress(self, GetTotalProgressPercent(self.animState, percent));

			self:TryShaking(elapsed, (1.0 - percent) * .8, .05);
			if now >= animContextData.endTime then
				self:SetAnimState(self.ANIM_STATE_NONE);
			end
		end
	end
end

function AzeriteEmpoweredItemTierMixin:SetAnimState(newAnimState, ...)
	if newAnimState ~= self.animState then
		self.animState = newAnimState;
		if newAnimState == self.ANIM_STATE_NONE then
			self.animContextData = nil;
		elseif newAnimState == self.ANIM_STATE_ROTATING then
			return;
		elseif newAnimState == self.ANIM_STATE_START_HOLD then
			if not self:IsFinalTier() then
				self.loopingSoundEmitter:StartLoopingSound();
			end
			self:InitializeLockInAnimation(...);
		elseif newAnimState == self.ANIM_STATE_END_HOLD then
			local now = GetTime();
			self.animContextData[newAnimState].startTime = now;
			self.animContextData[newAnimState].endTime = now + self.animContextData[newAnimState].endDuration;
		end

		self.owningFrame:OnTierAnimationStateChanged(self, newAnimState == self.ANIM_STATE_START_HOLD);
		self:UpdatePowerStates();
	end
end

function AzeriteEmpoweredItemTierMixin:PlayLockedInEffect()
	if self.tierSlot then
		self.tierSlot:PlayLockedInEffect();
	end
end

function AzeriteEmpoweredItemTierMixin:InitializeLockInAnimation(azeritePowerButton)
	local now = GetTime();

	if self:IsFinalTier() then
		local START_HOLD_TIME = .35;
		local LOCK_HOLD_TIME = .35;

		self.animContextData = 
		{
			azeritePowerButton = azeritePowerButton,

			[self.ANIM_STATE_START_HOLD] = 
			{
				startTime = now,
				endTime = now + START_HOLD_TIME,
			},

			[self.ANIM_STATE_ROTATING] = 
			{
				startTime = now + START_HOLD_TIME,
				durationSec = 1.5,
				hasPlayedLockInEffect = false,
				hasPlayedEndingClickSound = false,
			},

			[self.ANIM_STATE_END_HOLD] = 
			{
				endDuration = LOCK_HOLD_TIME,
			},
		};
	else
		local START_HOLD_TIME = .5;
		local LOCK_HOLD_TIME = .5;

		local startAngle = self.transformNode:GetLocalRotation();
		local endAngle = azeritePowerButton:GetBaseAngle();
		local angleDelta = math.atan2(math.sin(endAngle - startAngle), math.cos(endAngle - startAngle));

		local DISTANCE_PER_SEC = math.pi * .35;

		self.animContextData = 
		{
			azeritePowerButton = azeritePowerButton,

			[self.ANIM_STATE_START_HOLD] = 
			{
				startTime = now,
				endTime = now + START_HOLD_TIME,
			},

			[self.ANIM_STATE_ROTATING] = 
			{
				startAngle = startAngle,
				angleDelta = angleDelta,
				startTime = now + START_HOLD_TIME,
				durationSec = math.abs(angleDelta) / DISTANCE_PER_SEC,
				hasPlayedLockInEffect = false,
				hasPlayedEndingClickSound = false,
			},

			[self.ANIM_STATE_END_HOLD] = 
			{
				endDuration = LOCK_HOLD_TIME,
			},
		};
	end

	if self.tierPlug then
		self.tierPlug:Hide();
	end
end

function AzeriteEmpoweredItemTierMixin:IsAnimating()
	return self.animState ~= self.ANIM_STATE_NONE;
end

function AzeriteEmpoweredItemTierMixin:OnPowerSelected(azeritePowerButton)
	self:TransitionBackgroundGlow(self.BACKGROUND_GLOW_STATE_SELECTED);

	if self.rankFrame then
		self.rankFrame.SelectedAnim:Play();
	end

	self:SetAnimState(self.ANIM_STATE_START_HOLD, azeritePowerButton);
end

function AzeriteEmpoweredItemTierMixin:SetNodeRotations(rotationRads)
	self.transformNode:SetLocalRotation(rotationRads);
	if self.animatedGearNode then
		self.animatedGearNode:SetLocalRotation(-rotationRads * INNER_GEAR_ANIM_RATE);
	end
end

function AzeriteEmpoweredItemTierMixin:SnapToSelection()
	if not self:IsAnimating() then
		local selectedPowerID = self:GetSelectedPowerID();
		if selectedPowerID and not self:IsFinalTier() then
			local azeritePowerButton = self:GetAzeritePowerButtonByID(selectedPowerID);
			self:SetNodeRotations(azeritePowerButton:GetBaseAngle());
		else
			self:SetNodeRotations(0.0);
		end
	end
end

function AzeriteEmpoweredItemTierMixin:GetTierIndex()
	return self.tierIndex;
end

function AzeriteEmpoweredItemTierMixin:IsFinalTier()
	return self.isFinalTier;
end

function AzeriteEmpoweredItemTierMixin:GetSelectedPowerID()
	return self.selectedPowerID;
end

function AzeriteEmpoweredItemTierMixin:HasAnySelected()
	return self:GetSelectedPowerID() ~= nil;
end

function AzeriteEmpoweredItemTierMixin:IsSelectionActive()
	if self:HasAnySelected() then
		return false;
	end

	if self.azeriteItemDataSource:IsPreviewSource() then
		return false;
	end

	if self.prereqTier then
		if not self.prereqTier:HasAnySelected() then
			return false;
		end
	end

	return self.meetsPowerLevelRequirement;
end

function AzeriteEmpoweredItemTierMixin:IsPowerButtonAnimatingSelection(azeritePowerButton)
	return self.animContextData and self.animContextData.azeritePowerButton == azeritePowerButton or false;
end

function AzeriteEmpoweredItemTierMixin:GetAzeritePowerButtonByID(azeritePowerID)
	for powerIndex, azeritePowerButton in ipairs(self.azeritePowerButtons) do
		if azeritePowerButton:GetAzeritePowerID() == azeritePowerID then
			return azeritePowerButton;
		end
	end
	return nil;
end