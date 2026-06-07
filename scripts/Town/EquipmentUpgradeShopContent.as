class EquipmentUpgradeShopContent : AShopContent
{
	EquipmentUpgradeShopContent() {}
	EquipmentUpgradeShopContent(UnitPtr u, SValue& params) { super(u, params); }

	string GetName() override { return ".npc.shop.equipment_upgrade"; }
	string GetEmptyShopText() override { return ".npc.shop.equipment_upgrade.empty"; }

	AWindowObject@ MakeShopWindow(GUIBuilder@ guiBuilder) override
	{
		@m_window = BlacksmithEquipmentWindow(guiBuilder, this);
		return m_window;
	}

	array<IShopItem@> GetItems() override
	{
		array<IShopItem@> ret;
		for (uint i = 0; i < m_player.equipped.m_items.length(); i++)
		{
			auto item = m_player.equipped.m_items[i];
			if (item is null)
				continue;
			auto eqItem = cast<Equipment::Item>(item);
			if (eqItem is null)
				continue;

			auto nextBase = GetNextTierBaseItem(eqItem.baseItem);
			
			// Show the item if it can be level-upgraded OR tier-upgraded
			int maxUpgradeLevel = 9;
			if (eqItem.GetQuality() == Item::Quality::Epic)
				maxUpgradeLevel += 10;

			bool canLevelUp = (eqItem.upgradeLevel <= maxUpgradeLevel);
			bool canTierUpgrade = (nextBase !is null);

			if (canLevelUp || canTierUpgrade)
				ret.insertLast(EquipmentUpgradeShopItem(this, eqItem, nextBase, i, canLevelUp));
		}
		return ret;
	}
}

class EquipmentUpgradeShopItem : IShopItem
{
	EquipmentUpgradeShopContent@ m_shop;
	Equipment::Item@ m_item;
	Equipment::BaseItem@ m_nextBase;
	uint m_index;
	
	ShopCost@ m_levelUpCost;
	ShopCost@ m_tierUpgradeCost;

	Equipment::Item@ m_itemLevelUp;
	Equipment::Item@ m_itemTierUpgrade;

	EquipmentUpgradeShopItem(EquipmentUpgradeShopContent@ shop, Equipment::Item@ item, Equipment::BaseItem@ nextBase, uint index, bool canLevelUp)
	{
		@m_shop = shop;
		@m_item = item;
		@m_nextBase = nextBase;
		m_index = index;

		// Calculate level up cost (original blacksmith formulas)
		if (canLevelUp)
		{
			int costMul = 1;
			if (m_item.GetQuality() == Item::Quality::Epic)
				costMul = 2;
			
			@m_levelUpCost = ShopCost(MaterialType::Gold, costMul * max(100, int(int(m_item.itemLevel) + pow(float(m_item.upgradeLevel), 1.5f) * 5 - shop.m_shopLevel * 5) * 25));
			m_levelUpCost.AddCost(MaterialType::Iron, costMul * max(0, (int(m_item.upgradeLevel) - 1 + ((int(m_item.itemLevel) + 5 - shop.m_shopLevel * 2) / 10))) / 2);
			
			if (m_item.GetQuality() == Item::Quality::Epic)
				m_levelUpCost.AddCost(MaterialType::Ore, int(ceil(max(0, 2 + m_item.upgradeLevel - shop.m_shopLevel) / 10.0f) + m_item.itemLevel / 80.0f));

			@m_itemLevelUp = cast<Equipment::Item>(m_item.Copy());
			m_itemLevelUp.upgradeLevel++;
			m_itemLevelUp.Finalize(m_itemLevelUp.intensity, int(m_itemLevelUp.itemLevel), int(m_itemLevelUp.upgradeLevel), m_itemLevelUp.colorA, m_itemLevelUp.colorB);
		}

		// Calculate tier upgrade cost
		if (m_nextBase !is null)
		{
			int nextTier = 2;
			int tier = 1;
			string letter = "";
			ParseSuffix(GetSuffix(m_item.baseItem.m_id), tier, letter);
			ParseSuffix(GetSuffix(m_nextBase.m_id), nextTier, letter);

			int goldCost = 500;
			int ironCost = 2;
			if (nextTier == 3)
			{
				goldCost = 1500;
				ironCost = 5;
			}
			else if (nextTier >= 4)
			{
				goldCost = 5000;
				ironCost = 10;
			}

			@m_tierUpgradeCost = ShopCost(MaterialType::Gold, goldCost);
			m_tierUpgradeCost.AddCost(MaterialType::Iron, ironCost);

			@m_itemTierUpgrade = cast<Equipment::Item>(m_item.Copy());
			@m_itemTierUpgrade.baseItem = m_nextBase;
			m_itemTierUpgrade.Finalize(m_itemTierUpgrade.intensity, m_nextBase.ilvl, int(m_itemTierUpgrade.upgradeLevel), m_itemTierUpgrade.colorA, m_itemTierUpgrade.colorB);
		}
	}

	string GetID() { return m_index; }
	uint GetIDHash() { return m_index; }
	string GetTitle() { return "\\c" + Item::QualityColorString(m_item.GetQuality()) + m_item.GetName(); }
	string GetSubTitle() { return Resources::GetString(".tooltip.equipment.ilvl", {{"ilvl", m_item.GetItemLevelText()}}); }
	string GetDescription() { return ""; }
	ScriptSprite@ GetIcon() { return m_item.GetIcon(); }
	Sprite@ GetBackground() { return GetQualitySprite(m_item.GetQuality()); }
	ShopCost@ GetCost() { return null; }
	bool AutoSpendCost() { return false; }
	string OnFunc() { return "upgrade"; }
	bool IsAvailable(PlayerRecord@ player) { return true; }

	void ShowTooltip(WindowManager@ manager, bool compare) 
	{
		ShowTooltip(manager, compare, false, false);
	}

	void ShowTooltip(WindowManager@ manager, bool compare, bool levelUpPreview, bool tierUpgradePreview)
	{
		Equipment::Item@ previewItem = m_item;
		
		if (levelUpPreview)
			@previewItem = m_itemLevelUp;
		else if (tierUpgradePreview)
			@previewItem = m_itemTierUpgrade;
		
		if (previewItem is null)
			return;

		ITooltip@ tt = null;
		if (compare)
			@tt = Item::BuildCompareItemTooltip(previewItem, previewItem.GetPrice());
		else
			@tt = Item::BuildItemTooltip(previewItem, previewItem.GetPrice(), 1, false);
		
		manager.SetTooltip(tt, true);
	}

	Item::Item@ GetItem() { return m_item; }
}

class BlacksmithEquipmentWindow : ShopWindow
{
	Widget@ m_entryTemplate;

	BlacksmithEquipmentWindow(GUIBuilder@ b, AShopContent@ content)
	{
		super(b, content, "gui/shops/blacksmith_equipment.gui");
		@m_entryTemplate = m_widget.GetWidgetById("entry-template");
		Refresh();
	}

	void Refresh() override
	{
		if (m_entryTemplate is null)
			return;
		
		m_shopItems = m_shopContent.GetItems();
		
		@m_itemList = cast<ScrollbarWidget>(m_widget.GetWidgetById("equipment-list"));
		m_itemList.m_enabled = true;
		m_itemList.ClearChildren();
		
		m_widget.GetWidgetById("equipment").m_visible = true;
		
		for (uint i = 0; i < m_shopItems.length(); i++)
		{
			auto currItem = cast<EquipmentUpgradeShopItem>(m_shopItems[i]);
			auto entry = cast<EnchantEquipmentItem>(m_entryTemplate.Clone());
			entry.SetID(currItem.m_index);
			entry.m_visible = true;
			
			entry.SetTitle(currItem.GetTitle());
			entry.SetIcon(currItem.GetIcon());
			@entry.m_shopItem = currItem;
			
			// Setup button-1 for Level +1
			auto btnLevel = cast<EntryShopEnchantEquipmentItemOption>(entry.GetWidgetById("button-1"));
			if (currItem.m_levelUpCost !is null)
			{
				btnLevel.m_visible = true;
				btnLevel.SetTitle(Resources::GetString(".menu.blacksmith.level_up_button"));
				btnLevel.SetCostText(currItem.m_levelUpCost.GetText(m_shopContent.m_player, true));
				btnLevel.m_funcConfirm = "level_up";
				btnLevel.m_navPos.y = i;
				@btnLevel.m_shopItem = currItem;
			}
			else
			{
				btnLevel.m_visible = false;
			}
			
			// Setup button-2 for Tier Upgrade
			auto btnTier = cast<EntryShopEnchantEquipmentItemOption>(entry.GetWidgetById("button-2"));
			if (currItem.m_tierUpgradeCost !is null)
			{
				btnTier.m_visible = true;
				string nextTierName = currItem.m_nextBase.name;
				btnTier.SetTitle(Resources::GetString(".menu.blacksmith.tier_up_button", {{"tier", nextTierName}}));
				btnTier.SetCostText(currItem.m_tierUpgradeCost.GetText(m_shopContent.m_player, true));
				btnTier.m_funcConfirm = "tier_upgrade";
				btnTier.m_navPos.y = i;
				@btnTier.m_shopItem = currItem;
			}
			else
			{
				btnTier.m_visible = false;
			}
			
			m_itemList.AddChild(entry);
		}
		
		auto emptyPrompt = cast<TextWidget>(m_widget.GetWidgetById("empty"));
		if (emptyPrompt !is null)
		{
			if (m_itemList.m_children.length() > 0)
				emptyPrompt.SetText("");
			else
				emptyPrompt.SetText(Resources::GetString(".menu.blacksmith.no_upgrades"));
		}
		
		if (m_currencyText !is null)
		{
			auto record = GetLocalPlayerRecord();
			StringBuilder sb;
			
			sb += Resources::GetString(".tab.overlay.player.gold", {{ "amount", record.GetMaterial(MaterialType::Gold) }});
			sb += " ";
			sb += Resources::GetString(".tab.overlay.player.iron", {{ "amount", record.GetMaterial(MaterialType::Iron) }});
			sb += " ";
			sb += Resources::GetString(".tab.overlay.player.ore", {{ "amount", record.GetMaterial(MaterialType::Ore) }});
			
			m_currencyText.SetText(sb.String());
		}
		
		MakeNavTexts();
	}

	void MakeNavTexts()
	{
		if (m_navigationBar is null)
			return;
		
		auto currInteractable = m_input.GetCurrentInteractable();
		if (currInteractable is null)
			return;
		
		array<string>@ rawTexts = currInteractable.NavigationBarText();
		array<KeyNavigationText@> navTexts;
		for (uint i = 0; i < rawTexts.length(); i++)
			navTexts.insertLast(KeyNavigationText(m_navigationBar.m_font.BuildText(rawTexts[i])));
		
		navTexts.insertLast(KeyNavigationText(m_navigationBar.m_font.BuildText(FormatKeyName(GetActionBinding("MenuContext")) + " " + Resources::GetString(".menu.nav.compare")), WindowInput::OnFunc(this.MenuContext)));
		
		m_navigationBar.BuildBar(navTexts, this);
	}

	void RefreshKeybinds(ControlMap@ currMap) override
	{
		MakeNavTexts();
	}

	void OnInteractableIndexChanged() override
	{
		MakeNavTexts();

		if (m_itemList is null)
			return;

		m_manager.CloseTooltip();

		if (m_closeButton !is null && m_input.m_mouseOnlyHovering is m_closeButton)
			return;

		auto curr = m_itemList.m_input.GetCurrentInteractable();
		int refIndex = -1;
		Widget@ entry = curr;
		while (entry !is null)
		{
			refIndex = m_itemList.m_children.findByRef(entry);
			if (refIndex != -1)
				break;
			@entry = entry.m_parent;
		}

		if (refIndex == -1)
			return;

		auto shopItem = cast<EquipmentUpgradeShopItem>(m_shopItems[refIndex]);
		if (shopItem !is null)
		{
			bool isLevelUp = false;
			bool isTierUpgrade = false;
			Widget@ w = curr;
			while (w !is null)
			{
				if (w.m_id == "button-1")
					isLevelUp = true;
				else if (w.m_id == "button-2")
					isTierUpgrade = true;
				@w = w.m_parent;
			}

			shopItem.ShowTooltip(m_manager, false, isLevelUp, isTierUpgrade);
		}
	}

	void MenuContext() override
	{
		if (!m_shopContent.ShowInfo())
			return;

		auto curr = m_itemList.m_input.GetCurrentInteractable();
		int refIndex = -1;
		Widget@ entry = curr;
		while (entry !is null)
		{
			refIndex = m_itemList.m_children.findByRef(entry);
			if (refIndex != -1)
				break;
			@entry = entry.m_parent;
		}

		if (refIndex == -1)
			return;

		auto shopItem = cast<EquipmentUpgradeShopItem>(m_shopItems[refIndex]);
		if (shopItem !is null)
		{
			bool isLevelUp = false;
			bool isTierUpgrade = false;
			Widget@ w = curr;
			while (w !is null)
			{
				if (w.m_id == "button-1")
					isLevelUp = true;
				else if (w.m_id == "button-2")
					isTierUpgrade = true;
				@w = w.m_parent;
			}

			shopItem.ShowTooltip(m_manager, true, isLevelUp, isTierUpgrade);
		}
	}

	void OnFunc(Widget@ sender, const string &in name) override
	{
		ShopWindow::OnFunc(sender, name);
		
		if (name == "level_up")
		{
			auto entryOption = cast<EntryShopEnchantEquipmentItemOption>(sender);
			if (entryOption is null || entryOption.m_shopItem is null)
				return;
			
			auto shopItem = cast<EquipmentUpgradeShopItem>(entryOption.m_shopItem);
			if (shopItem is null || shopItem.m_levelUpCost is null)
				return;
			
			if (!shopItem.m_levelUpCost.CanAfford(m_shopContent.m_player))
				return;
			
			shopItem.m_levelUpCost.Spend(m_shopContent.m_player);
			
			auto getEquip = shopItem.m_item;
			getEquip.upgradeLevel++;
			getEquip.Finalize(getEquip.intensity, int(getEquip.itemLevel), int(getEquip.upgradeLevel), getEquip.colorA, getEquip.colorB);
			print("Upgraded level of item " + getEquip.GetName() + " to +" + getEquip.upgradeLevel);
			
			Refresh();
			RefreshInteractableWidgets(m_widget);
			
			m_shopContent.m_player.RefreshModifiers();
		}
		else if (name == "tier_upgrade")
		{
			auto entryOption = cast<EntryShopEnchantEquipmentItemOption>(sender);
			if (entryOption is null || entryOption.m_shopItem is null)
				return;
			
			auto shopItem = cast<EquipmentUpgradeShopItem>(entryOption.m_shopItem);
			if (shopItem is null || shopItem.m_tierUpgradeCost is null || shopItem.m_nextBase is null)
				return;
			
			if (!shopItem.m_tierUpgradeCost.CanAfford(m_shopContent.m_player))
				return;
			
			shopItem.m_tierUpgradeCost.Spend(m_shopContent.m_player);
			
			auto getEquip = shopItem.m_item;
			@getEquip.baseItem = shopItem.m_nextBase;
			getEquip.Finalize(getEquip.intensity, shopItem.m_nextBase.ilvl, int(getEquip.upgradeLevel), getEquip.colorA, getEquip.colorB);
			print("Upgraded tier of item " + getEquip.GetName() + " to " + shopItem.m_nextBase.name);
			
			Refresh();
			RefreshInteractableWidgets(m_widget);
			
			m_shopContent.m_player.RefreshModifiers();
		}
		else if (name == "close")
		{
			m_manager.CloseTooltip();
			m_closing = true;
		}
	}
}

string GetSuffix(string id)
{
	int lastUnderscore = -1;
	for (int i = 0; i < int(id.length()); i++)
	{
		if (id.substr(i, 1) == "_")
			lastUnderscore = i;
	}
	if (lastUnderscore == -1)
		return "";
	return id.substr(lastUnderscore + 1);
}

string GetBaseID(string id)
{
	int lastUnderscore = -1;
	for (int i = 0; i < int(id.length()); i++)
	{
		if (id.substr(i, 1) == "_")
			lastUnderscore = i;
	}
	if (lastUnderscore == -1)
		return id;
	return id.substr(0, lastUnderscore);
}

bool ParseSuffix(string suffix, int &out tier, string &out letter)
{
	tier = 0;
	letter = "";
	if (suffix.length() == 0)
		return false;

	int i = 0;
	if (suffix.substr(0, 1) == "t") {
		i++;
	}

	string numStr = "";
	while (i < int(suffix.length())) {
		string c = suffix.substr(i, 1);
		if (c == "0" || c == "1" || c == "2" || c == "3" || c == "4" || c == "5" || c == "6" || c == "7" || c == "8" || c == "9") {
			numStr += c;
			i++;
		} else {
			break;
		}
	}

	if (numStr.length() == 0)
		return false;

	tier = parseInt(numStr);
	if (i < int(suffix.length())) {
		letter = suffix.substr(i);
	}
	return true;
}

Equipment::BaseItem@ GetNextTierBaseItem(Equipment::BaseItem@ baseItem)
{
	if (baseItem is null)
		return null;

	string id = baseItem.m_id;
	string baseID = GetBaseID(id);
	string suffix = GetSuffix(id);

	int tier = 0;
	string letter = "";
	if (!ParseSuffix(suffix, tier, letter))
		return null;

	bool startsWithT = (suffix.length() > 0 && suffix.substr(0, 1) == "t");
	bool padZero = (suffix.length() > 0 && suffix.substr(0, 1) == "0");

	for (int nextTier = tier + 1; nextTier <= 10; nextTier++)
	{
		string nextSuffix = "";
		if (startsWithT)
			nextSuffix += "t";
		
		if (padZero && nextTier < 10)
			nextSuffix += "0";
		
		nextSuffix += nextTier;
		nextSuffix += letter;

		string nextID = baseID + "_" + nextSuffix;
		auto nextItem = Equipment::BaseItem::Get(nextID);
		if (nextItem !is null)
			return nextItem;
	}

	return null;
}
