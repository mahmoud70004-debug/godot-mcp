# Rotten Crown — البنية البرمجية

## شجرة المجلدات

```
rotten-crown/
├── project.godot            إعدادات المشروع (Mobile، 640×360، أفقي، خريطة المدخلات، طبقات الفيزياء)
├── export_presets.cfg       إعداد تصدير Android (arm64، immersive)
├── default_bus_layout.tres  قنوات الصوت: Master / Music / SFX (صدى) / Ambience (Low-pass)
├── assets/
│   ├── shaders/             retro_post, flesh, ooze, moon
│   ├── ui/rotten_theme.tres الثيم العام لواجهة المستخدم
│   └── textures|models|audio|fonts/   (فارغة، للمرحلة 7)
├── data/                    كل المحتوى كموارد .tres، بحيث تُضاف محتويات جديدة دون برمجة
│   ├── items/{weapons,consumables,relics,lore}/
│   ├── enemies/
│   └── regions/
├── src/
│   ├── autoload/            الأنظمة العامة (Singletons)
│   ├── components/          Health / Hitbox / Hurtbox
│   ├── combat/              DamageInfo
│   ├── player/              Player + PlayerWeapon
│   ├── enemies/             Enemy (AI) + CreatureRig + EnemyData + hollow.tscn
│   ├── items/               ItemData وأنواعه + Inventory + WeaponModelBuilder
│   ├── interaction/         Interactable + ItemPickup
│   ├── world/               Level، RegionData و RegionTrigger، FlickerLight، AmbientDrone، Blockout
│   ├── rendering/           RetroMaterials + post_process.tscn
│   ├── ui/                  HUD، التحكم باللمس، الحقيبة، القائمة الرئيسية
│   ├── characters/          HumanoidRig + KnightModel + VillagerModel (شخصيات من أشكال بسيطة مع حركات إجرائية)
│   ├── cutscenes/           prologue.tscn + PrologueCutscene (مخرج اللقطات والنصوص)
│   └── levels/test/visual_test.tscn
├── tools/validate_project.py مدقّق ثابت للمراجع والمسارات
└── docs/
```

## الأنظمة العامة (Autoloads) — بترتيب التحميل

| الاسم | المسؤولية |
|---|---|
| `Events` | ناقل إشارات عام (Signal Bus). الأنظمة لا يعرف بعضها بعضاً، بل تتواصل عبره |
| `Settings` | الحساسية، وعكس المحور، والأصوات، وفرض أدوات اللمس. تُحفظ في `user://settings.cfg` |
| `GameState` | الحقيبة، والسلاح المُجهَّز، والترقيات، وأعلام القصة، والوثائق المكتشفة، والإحصاءات المشتقّة من الآثار. قابل للتحويل إلى JSON |
| `SaveManager` | حفظ وتحميل بصيغة JSON في `user://savegame.json` (نسخة بإصدار) |
| `AudioManager` | مجموعات مشغّلات SFX ثنائية وثلاثية الأبعاد، وانتقال سلس بين المقطوعات الموسيقية |
| `SceneLoader` | انتقال بالتلاشي إلى الأسود مع تحميل في الخلفية (Threaded) |

## تدفّق الضرر

```
PlayerWeapon.attack()
   └─ Tween: wind-up ─► HitboxComponent.activate() ─► swing ─► deactivate()
HitboxComponent (Area3D, mask=enemy_hurtbox)
   └─ لكل HurtboxComponent متداخل (مرة واحدة لكل ضربة) ─► receive_hit(DamageInfo)
HurtboxComponent
   ├─ damage_modifier (مثل الصدّ عند اللاعب) يعدّل الضربة
   └─ HealthComponent.take_damage() ─► damaged / health_changed / died
```
العدو يستعمل نفس الآلية بالعكس: `AttackHitbox` يستهدف قناع `player_hurtbox`.

### طبقات الفيزياء
| # | الاسم | من يستخدمها |
|---|---|---|
| 1 | world | الجدران والأرض، وخط الرؤية عند الأعداء |
| 2 | player | جسم اللاعب، و RegionTrigger |
| 3 | enemies | أجسام المخلوقات |
| 4 | interactables | العناصر القابلة للالتقاط والتفاعل (يكشفها RayCast اللاعب) |
| 5 | player_hurtbox | منطقة استقبال الضرر عند اللاعب |
| 6 | enemy_hurtbox | منطقة استقبال الضرر عند المخلوقات |

## المدخلات (Input)
كل شيء يمرّ عبر **Input Actions** في `project.godot`، بحيث لا يعرف كود اللعب مصدر المدخل:
- `TouchControls` تتبع كل إصبع بنفسها، لأن واجهة Godot الافتراضية تتعامل مع مؤشر واحد فقط.
  - `VirtualJoystick` يحوّل اللمس إلى `Input.action_press("move_*", strength)`، أي حركة تناظرية.
  - `TouchActionButton` يرسل `InputEventAction` حقيقياً (attack / block / interact).
  - السحب في النصف الأيمن يرسل `Events.look_input`.
- الفأرة لا تُستخدم إلا حين تكون ملتقطة (للاختبار على الحاسوب)، فأحداث الفأرة المحاكاة من اللمس لا تُحدث هجمات وهمية.
- Gamepad: العصا اليسرى للحركة، واليمنى للنظر، و RB هجوم، و LB صدّ، و A تفاعل، و Y حقيبة، و Start إيقاف.

## كيف تضيف محتوى جديداً (بدون برمجة غالباً)

| تريد إضافة | الخطوات |
|---|---|
| **سلاح** | انسخ `data/items/weapons/woodsman_axe.tres` وعدّل القيم و `weapon_type`، ثم ضع `item_pickup.tscn` في المستوى واربط الـ `item` |
| **وثيقة قصة** | أنشئ `LoreData` جديداً في `data/items/lore/`، ثم ضعه في Pickup |
| **مخلوق بنفس الهيكل** | أنشئ `EnemyData` جديداً، ثم ضع `hollow.tscn` في المستوى وغيّر `data` |
| **مخلوق بسلوك جديد** | اورث `Enemy` (`extends Enemy`)، وأعد تعريف `_should_wake` أو حالات الهجوم، واصنع Rig جديداً |
| **منطقة** | أنشئ `RegionData` ومشهداً جذره `Level`، وأضف `RegionTrigger` عند المدخل |
| **مادة بيكسل** | أضف دالة في `RetroMaterials` بلوحة ألوان جديدة |

## أدوات المطوّر
| الأداة | الوظيفة |
|---|---|
| `tools/render_shots.sh` | يصوّر لقطات من أي موقع بنفس مُصيِّر المتصفح (RC_SHOT="x,y,z,yaw,pitch") |
| `tools/gen_audio.py` | يولّد الموسيقى والأصوات المؤقتة كملفات WAV مع نقاط تكرار (Loop) |
| `tools/web_smoke_test.cjs` | اختبار المتصفح الكامل (قائمة، ثم تخطّي المشهد الافتتاحي، ثم مشي ونظر وهجوم وحقيبة) |
| `tools/web_touch_repro.cjs` | يمنع عودة خلل قفز الكاميرا مع ذراع التحكم |
| `tools/web_perf.cjs` | يقيس الإطارات في الثانية مع تعطيل ميزات عبر `?perf=` |
| `?debug=1` في الرابط | يعرض FPS وحالة اللمس على الشاشة (DebugBridge) |

## الأداء على الهاتف
- العرض داخلياً بدقّة 640×360 فقط، فتكلفة البكسلات ضئيلة.
- مُصيِّر **Mobile**، دون MSAA، وظلال قاسية، وظل واحد فقط (القمر).
- الأرض مقسّمة إلى مربّعات 20م، لأن مُصيِّر Mobile يسمح بثمانية أضواء Omni فقط لكل Mesh.
- أضواء الفوانيس بدون ظلال.
- **مُصيِّر المتصفح (Compatibility) يرسم كل جسم مرة إضافية لكل ضوء يلمسه.** لذلك:
  - `MeshMerger.merge_static` يدمج الـ Blockout في مجسّم واحد لكل (خامة × خلية 20م)، فيبقى أثر الضوء محلياً.
  - `MeshMerger.bake_character` يدمج قطع كل مفصل في مجسّم واحد بألوان الرؤوس (Vertex Colors).
  - العشب بلا إضاءة (Unshaded)، ومقسّم إلى أجزاء 12م، ويختفي بعد 40م.
  - الألعاب النارية بلا أضواء حقيقية.
- ضغط الخامات ETC2/ASTC مفعّل.
