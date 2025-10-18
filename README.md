# LootSense

[![Version](https://img.shields.io/github/v/release/pumpan/LootSense?color=blue\&label=version)](https://github.com/pumpan/LootSense/releases)
![WoW Version](https://img.shields.io/badge/WoW-1.12.1-ff69b4)
![License](https://img.shields.io/badge/license-MIT-green)
[![Latest ZIP](https://img.shields.io/badge/dynamic/json?color=success\&label=Latest\&query=$.assets\[0\].download_count\&url=https://api.github.com/repos/pumpan/LootSense/releases/latest)](https://github.com/pumpan/LootSense/releases/latest)

<p align="center">
  <a href="https://www.paypal.com/donate/?hosted_button_id=JCVW2JFJMBPKE" target="_blank">
    <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate with PayPal" style="border: 0;">
  </a>
  <br>
  💙 <a href="https://www.paypal.com/donate/?hosted_button_id=JCVW2JFJMBPKE" target="_blank">Support Me with PayPal</a>
</p>

---

## 🗃️ Table of Contents

* [Overview](#overview)
* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
* [Configuration](#configuration)
* [Changelog](#changelog)
* [License](#license)
* [Contact](#contact)

---

## 🧠 Overview

**LootSense** is a **smart loot management addon** for **World of Warcraft 1.12.1 (Vanilla)** that helps you automatically **keep, vendor, or delete** specific items based on your personal preferences.

When you loot an item, LootSense opens a small decision frame that gives you the options **Always Keep**, **Always Vendor**, **Always Delete**, or **Ignore**. Choosing *Ignore* means the addon will forget the item until you encounter it again.

Next time you loot an item you've marked, LootSense will automatically perform the chosen action — saving you time, bag space, and sanity.

And if you change your mind later, there’s a handy **Settings** menu accessible via the minimap button 
<p align="center">
  <img src="/LootSense/Screens/minimap.png" alt="Keep Button" width="25">
</p>

<p align="center">
  <img src="/LootSense/Screens/keep.jpg" alt="Keep Button" width="250">
  <img src="/LootSense/Screens/vendor.jpg" alt="Vendor Button" width="250">
  <img src="/LootSense/Screens/delete.jpg" alt="Delete Button" width="250">
</p>

## ⚠️ Warning

**LootSense** is a powerful automation addon that can automatically delete, vendor, or loot items based on your preferences.
Use it responsibly automated deletion is permanent and **cannot be undone**.

Before enabling any auto-delete settings, double-check your lists to make sure no valuable or rare items will be removed.
The author takes no responsibility for lost items due to incorrect configuration or misuse.

If you want to temporarily disable all automatic actions, use the “Pause LootSense” option under the Settings tab.

## 🛠️ Installation

1. **Download LootSense:**
[![⬇ DOWNLOAD](https://img.shields.io/github/downloads/pumpan/LootSense/total?style=for-the-badge&color=00b4d8&label=⬇+DOWNLOAD)](https://github.com/pumpan/LootSense/releases)


2. **Extract Files:**

   * Extract the contents into your WoW AddOns folder:

     ```
     World of Warcraft/Interface/AddOns
     ```
   * Make sure the folder name is exactly:

     ```
     LootSense
     ```

3. **Enable LootSense:**

   * Start WoW and enable the addon from the AddOns menu on the character selection screen.

---

## ✨ Features

* 🧠 **Smart Loot Filtering:**
  Automatically manage unwanted items through simple buttons — **Keep**, **Vendor**, or **Delete**.

* 💾 **Per-Character Saved Preferences:**
  Each character remembers what you’ve chosen to keep, sell, or trash.

* ⚙️ **Minimal & Efficient UI:**
  Lightweight design that integrates seamlessly into the vanilla interface.

* 🪙 **Auto Vendor Integration:**
  Automatically sells vendor-marked items when you open a merchant.

* 🗑️ **Auto Delete Functionality:**
  Instantly removes marked junk items when you loot.

* 🧩 **Clean Frame Logic:**
  The decision frame disappears automatically when all items have been handled.


---

## 🚀 Usage

1. **Loot an Item:**
   When an item appears in your loot window, LootSense will display three intuitive buttons:

   * 🟩 **Keep**
   * 🟨 **Vendor**
   * 🔴 **Delete**

2. **Make Your Choice:**
   Click the desired button for each item. LootSense will remember your choice automatically.

3. **Automatic Handling:**

   * Items marked **Keep** are stored as normal.
   * Items marked **Vendor** are sold automatically when you open a merchant.
   * Items marked **Delete** are destroyed automatically upon looting.

4. **Changing Your Mind:**

<p align="center">
  <img src="/LootSense/Screens/minimap.png" alt="Keep Button" width="25">
</p>
   Access the **Settings** via the minimap button or "/ls list" or the button in the top-right corner of the loot decision frame to modify or clear saved choices.
<p align="center">
  <img src="/LootSense/Screens/manage.jpg" alt="Keep Button" width="250">
</p>
---

## 🗾 Example Workflow

1. Loot a **Broken Fang** → Click 🔴 **Delete**
2. Loot a **Worn Shortsword** → Click 🟨 **Vendor**
3. Loot a **Runecloth** → Click 🟩 **Keep**

Next time you loot the same items, LootSense will **auto-handle them** instantly.

---

## 🗓️ Changelog

### **LootSense 1.0.0**

🆕 **Initial Release**

* Core loot decision logic implemented
* Auto vendor and auto delete functionality
* UI button system (Keep / Vendor / Delete)
* Per-character saved preferences
* Integration with WoW 1.12.1 client
* Lightweight memory footprint

---

## 📜 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## 📧 Contact

For feedback, suggestions, or bug reports — please open an issue on GitHub:
👉 [https://github.com/pumpan/LootSense/issues](https://github.com/pumpan/LootSense/issues)

Or support development via PayPal ❤️
[💙 Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=JCVW2JFJMBPKE)

---
