# Rotten Crown — البنية البرمجية

## شجرة المجلدات

```
rotten-crown/
├── project.godot            إعدادات المشروع (Mobile، 640×360، أفقي، خريطة المدخلات، طبقات الفيزياء، Autoloads)
├── export_presets.cfg       إعداد تصدير Android (arm64، immersive) وإعداد الويب
├── default_bus_layout.tres  قنوات الصوت: Master / Music / SFX (صدى) / Ambience (Low-pass)
├── assets/
│   ├── shaders/             retro_post, flesh, ooze, moon, night_sky, terrain, grass, moon_shaft, silhouette
│   ├── sprites/<char>/      أوراق Sprite المُخبَزة: <char>.png + <char>.tres (تُنتج بـ tools/bake_sprites.sh)
│   ├── materials/           grass_field.tres و grass_dry_tall.tres (عشب الحقول)
│   ├── ui/rotten_theme.tres الثيم العام لواجهة المستخدم
│   └── textures|models|audio|fonts/   (فارغة، للمرحلة 8)
├── data/                    كل المحتوى كموارد .tres، بحيث تُضاف محتويات جديدة دون برمجة
│   ├── items/{weapons,consumables,relics,lore}/
│   ├── enemies/             EnemyData (ويشمل sprite_sheet لكل مخلوق)
│   └── regions/             RegionData لكل منطقة
├── src/
│   ├── autoload/            الأنظمة العامة (Singletons)
│   ├── components/          Health / Hitbox / Hurtbox
│   ├── combat/              DamageInfo
│   ├── player/              Player + PlayerWeapon
│   ├── enemies/             Enemy (AI) + EnemyData + hollow.tscn + sprite_creature_visual.gd (الرسم بالـ Sprites)
│   │                        + creature_rig.gd (تحريك إجرائي، يُستعمل عند تخبيز الـ Sprites)
│   ├── items/               ItemData وأنواعه + Inventory + WeaponModelBuilder
│   ├── interaction/         Interactable + ItemPickup
│   ├── world/               Level، RegionData و RegionTrigger، FlickerLight، AmbientDrone، Blockout
│   │   ├── terrain_spec.gd + terrain_builder.gd   تضاريس بخريطة ارتفاع، مع الطرق وتلوين الرؤوس
│   │   ├── grass_scatter.gd                        توزيع العشب على قطع 12م
│   │   ├── overworld_spec.gd                       مواقع الطرق والمناطق بالأمتار
│   │   ├── regions/                                مُنشئو المناطق: thornfield / hollowmere / whispering_wood
│   │   ├── props/prop_kit.gd                       قطع البيئة: أسوار، أشجار، يقطين، كنيسة، أكواخ...
│   │   ├── weather_controller.gd                   المطر والبروق
│   │   └── horizon_backdrop.gd                     أفق بطبقات من التلال والأبراج
│   ├── levels/
│   │   ├── test/visual_test.tscn
│   │   └── valdron/         المملكة شبه المفتوحة
│   │       ├── valdron_overworld.tscn   المشهد الرئيسي لمرحلة الاستكشاف
│   │       ├── overworld_builder.gd     يجمع التضاريس والمناطق والطرق
│   │       ├── overworld_populator.gd   يضع المخلوقات والعناصر في مواقعها
│   │       └── baked/*.scn              العالم المُخبَز (overworld_world.scn، prologue_world.scn)
│   ├── rendering/           RetroMaterials + post_process.tscn
│   │   ├── pixel_sprite_3d.gd       PixelSprite3D: لوحة Sprite تواجه الكاميرا بثماني اتجاهات
│   │   ├── sprite_sheet_data.gd     SpriteSheetData + direction_index (اتفاقية الاتجاهات)
│   │   ├── quality_manager.gd       Autoload `Quality`: مستويات Low / Medium / High
│   │   └── mesh_merger.gd           دمج المجسّمات (merge_static / bake_character)
│   ├── ui/                  HUD، التحكم باللمس، الحقيبة، القائمة الرئيسية
│   ├── characters/          نماذج ثلاثية الأبعاد (HumanoidRig + KnightModel + VillagerModel)، تُخبز إلى Sprites ولا تُعرض مباشرة في اللعبة
│   └── cutscenes/           prologue.tscn + PrologueCutscene (مخرج اللقطات والنصوص)
├── tools/
│   ├── validate_project.py  مدقّق ثابت للمراجع والمسارات
│   ├── bake_world.sh/.gd/.tscn   بناء العالم إلى مشاهد ثنائية
│   ├── bake_sprites.sh      تصوير الشخصيات وتحويلها إلى أوراق بيكسل
│   ├── pixelize_sprites.py  تصغير الصور وتكميم اللوحة وتجميع الأوراق
│   ├── sprite_baker/        مشهد التصوير (sprite_baker.tscn)، characters.json، creature_rig.tscn
│   └── galleries/           معارض معاينة: region_preview، terrain_preview، sprite_preview، prop_gallery، knight_turntable، quality_check
└── docs/
```

## الأنظمة العامة (Autoloads) — بترتيب التحميل

| الاسم | المسؤولية |
|---|---|
| `Events` | ناقل إشارات عام (Signal Bus). الأنظمة لا يعرف بعضها بعضاً، بل تتواصل عبره |
| `Settings` | الحساسية، وعكس المحور، والأصوات، وفرض أدوات اللمس، ومستوى الجودة. تُحفظ في `user://settings.cfg` |
| `GameState` | الحقيبة، والسلاح المُجهَّز، والترقيات، وأعلام القصة، والوثائق المكتشفة، والإحصاءات المشتقّة من الآثار. قابل للتحويل إلى JSON |
| `SaveManager` | حفظ وتحميل بصيغة JSON في `user://savegame.json` (نسخة بإصدار) |
| `AudioManager` | مجموعات مشغّلات SFX ثنائية وثلاثية الأبعاد، وانتقال سلس بين المقطوعات الموسيقية |
| `Quality` | تطبيق مستوى الجودة Low / Medium / High (دقة العرض، والظلال، وكثافة العشب، وطبقة المطر)، والخفض التلقائي عند انخفاض الإطارات. الملف: `src/rendering/quality_manager.gd` |
| `SceneLoader` | انتقال بالتلاشي إلى الأسود مع تحميل في الخلفية (Threaded) |
| `DebugBridge` | طبقة `?debug=1` (FPS وحالة اللمس)، ونشر `window.rcState` لاختبارات المتصفح عبر `register(key, Callable)` |

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

### أنماط هجوم المخلوقات (`EnemyData`، مجموعة "Attack style")
كل الأنماط بيانات فقط، ولا حاجة لصنف فرعي من `Enemy`:
- `LUNGE`: اندفاعة للأمام (السلوك الافتراضي).
- `STAB`: دفعة قصيرة في أول 40% من `attack_active_time`، وتعتمد على صندوق ضرر طويل (`hit_box_size` / `hit_box_offset`).
- `LEAP`: قفزة بسرعة رأسية `leap_up_speed` مع اندفاعة `lunge_speed` والصندوق فعّال طوال القفزة.
- `SLAM`: عند بدء التحضير تُقفل نقطة الهبوط عند موضع اللاعب (حتى `attack_range` + 0.5 م) ويظهر ظل أرضي (`SlamTelegraph`) يكبر حتى `slam_radius`؛ وعند الضربة ينتقل صندوق الضرر إلى النقطة المقفلة (أسطوانة) ويصيب مرة واحدة.
- `windup_tremble`: اهتزاز بصري أثناء التحضير يزداد مع التقدّم. `skitter_burst` / `skitter_pause`: مطاردة على دفعات (±30% عشوائية).

## أدوات المطوّر
| الأداة | الوظيفة |
|---|---|
| `tools/render_shots.sh` | يصوّر لقطات من أي موقع بنفس مُصيِّر المتصفح (RC_SHOT="x,y,z,yaw,pitch") |
| `tools/gen_audio.py` | يولّد الموسيقى والأصوات المؤقتة كملفات WAV مع نقاط تكرار (Loop) |
| `tools/web_smoke_test.cjs` | اختبار المتصفح الكامل (قائمة، ثم تخطّي المشهد الافتتاحي، ثم مشي ونظر وهجوم وحقيبة) |
| `tools/web_touch_repro.cjs` | يمنع عودة خلل قفز الكاميرا مع ذراع التحكم |
| `tools/bake_world.sh [overworld\|prologue]` | يبني العالم بمحرك Godot بلا واجهة (`RC_BAKE=overworld` أو `prologue`) ويحفظه كمشاهد ثنائية `.scn` في `src/levels/valdron/baked/`. يُعاد تشغيله بعد كل تعديل على العالم، ويتطلب متغير `GODOT` |
| `tools/bake_sprites.sh [char]` | يصوّر الشخصيات من ثماني اتجاهات عبر `tools/sprite_baker/` تحت xvfb، ثم يحوّلها بـ `pixelize_sprites.py` إلى `assets/sprites/<char>/`. بدون معامل يبني الكل، ويقبل قائمة مفصولة بفواصل |
| `tools/pixelize_sprites.py` | يصغّر الصور الخام، ويكمّم اللوحة اللونية، ويضيف الحد الأسود، ويجمع الأوراق ويكتب ملف `.tres` لكل ورقة |
| `tools/galleries/region_preview.tscn` | معاينة مناطق الخريطة على التضاريس الحقيقية: `RC_REGION=thornfield\|hollowmere\|whispering_wood` و`RC_CAM="x,y,z,lx,ly,lz"` |
| `tools/galleries/terrain_preview.tscn` | معاينة التضاريس والطرق والحقول بكاميرا `RC_CAM="x,y,z,lx,ly,lz"` |
| `tools/web_perf.cjs` | يقيس إطارات الثانية في اللعب مع تعطيل ميزات (`nosky`، `nograss`، `nohorizon`، `nopost`، `nofog`) عبر `?perf=`، للمقارنة بين النسخ. الأرقام من متصفح برمجي وليست أرقام هاتف |
| `?debug=1` في الرابط | يعرض FPS وحالة اللمس على الشاشة (DebugBridge) |

## الأداء على الهاتف
- العرض داخلياً بدقّة 640×360 فقط، فتكلفة البكسلات ضئيلة.
- مُصيِّر **Mobile**، دون MSAA، وظلال قاسية، وظل واحد فقط (القمر).
- الأرض تُبنى كقطع (Chunks) من خريطة الارتفاع، لأن مُصيِّر Mobile يسمح بثمانية أضواء Omni فقط لكل Mesh.
- أضواء الفوانيس بدون ظلال.
- **مُصيِّر المتصفح (Compatibility) يرسم كل جسم مرة إضافية لكل ضوء يلمسه.** لذلك:
  - `MeshMerger.merge_static` يدمج المجسّمات الثابتة في مجسّم واحد لكل (خامة × خلية)، فيبقى أثر الضوء محلياً.
  - `MeshMerger.bake_character` يدمج قطع كل مفصل في مجسّم واحد بألوان الرؤوس (Vertex Colors).
  - العشب بلا إضاءة (Unshaded)، ومقسّم إلى قطع 12م ويختفي بعد نحو 40م.
  - الألعاب النارية بلا أضواء حقيقية.
- ضغط الخامات ETC2/ASTC مفعّل.
- **"اخبز، لا تولّد"**: العالم والمشهد الافتتاحي يُبنيان خارج اللعبة (`tools/bake_world.sh`) ويُحفظان كمشاهد ثنائية `.scn`. اللعبة تحمّلها فقط، ولا تنفّذ حلقات بناء بـ GDScript عند التشغيل.
- **Sprites بدل مجسّمات الشخصيات**: كل شخصية لوحة واحدة (Billboard) بدل عشرات القطع، فتكلفة الرسم ضئيلة وثابتة.
- **مدى ظهور لكل مجموعة**: قطع الأرض (`TerrainSpec.chunk_size` = 64م) تُخفى بعد 170م، والمجسّمات المدمجة تحمل `visibility_range_end` خاصاً بها، فلا يُرسم ما لا يُرى.
- **مستويات جودة Low / Medium / High** (Autoload `Quality`): تغيّر دقة العرض الداخلية، والظلال، وكثافة العشب، وطبقة المطر، مع خفض تلقائي إلى Low عند انخفاض الإطارات.
