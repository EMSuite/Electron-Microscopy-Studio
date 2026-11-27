# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). App versions are tagged with a `v`
(`v1.0.0`); release-please writes each new entry above the older ones from the merged pull requests' titles.

## [2.6.1](https://github.com/EMSuite/Electron-Microscopy-Studio/compare/v2.6.0...v2.6.1) (2026-11-27)


### Bug Fixes

* the EDS energy axis is refined from 0.6 keV up, on the kits of 26 Nov (FormatoKit 0.22.0, ImagoKit 0.12.0, SpectroKit 0.17.2, SimulatoKit 0.8.1) ([#1163](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1163)) ([8ef2eb2](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8ef2eb215db039212cbae5376445a1c4206b60da))

## [2.6.0](https://github.com/EMSuite/Electron-Microscopy-Studio/compare/v2.1.1...v2.6.0) (2026-11-27)


### Features

* a document keeps its links to other files ([#993](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/993)) ([706d0d5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/706d0d5992c7344cc583f8b31551ee0731c0456c))
* a phase is saved as CIF ([#996](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/996)) ([6426a13](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/6426a13e051a84aa68a720fd0f32e99bad1a5255))
* a simulated CBED pattern follows the hand tilt, so Measure Thickness closes on it ([#1015](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1015)) ([e771e16](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/e771e16bde259743daf48466706873fe3e4cc9d7))
* a Simulation document saves to and reopens from its session file ([#989](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/989)) ([a81cf55](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a81cf5585fe4460112a1ce9b5787d0ab7b32198c))
* a Simulation document's Microscope and Orientation sections, and R in mm ([#970](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/970)) ([f3df1ff](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/f3df1ffffe1d50d8256c5c73e9a064704af6a505))
* a spot pattern and a silicon structure in the demo data ([#1000](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1000)) ([49386ef](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/49386efd5185feef585094b54120df8094e81984))
* agents can work every room through the agent door ([#845](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/845)) ([8b9f09a](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8b9f09a5d2814ea0b8a2078daa4b6405d87f6189))
* an agent opens a file of its Agent folder as File &gt; Open does ([#830](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/830)) ([88be328](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/88be328d42318f93e91b061c647d3a38e84f295a))
* app foundations: colourless overlays, crash reports, recent files, first-run journey, door regions, snapshot tests and How to Cite ([#892](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/892)) ([86c0b24](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/86c0b24c44d2df209d0809439c6917b81ef257ab))
* CBED with a thickness series ([#912](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/912)) ([abff3a4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/abff3a4d2675fbff44de21abdc5f89a8c9413713))
* charts, maps and result tables leave the inspector for panes of the room ([#997](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/997)) ([23a38db](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/23a38db06c34b94bd7d0c2393791ca4257d6a9e0))
* Diffraction in steps, a readable indexed pattern, Simulate and Export in the toolbar ([#1052](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1052)) ([49b5e51](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/49b5e51dd316b6345be94e7b857cdad318e34171))
* diffraction science in the Diffraction room: Holder and zone-axis map, powder patterns, Find Phases, precipitate variants with double diffraction ([#954](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/954)) ([3d2336c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/3d2336ca307322274f1bce4dc10400d05b592c79))
* door tools for CBED, STEM images, atom models, thickness from CBED and strain maps ([#995](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/995)) ([cc9326c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/cc9326c8e7c1e3f73aa17b18e243bf8cf80ed48e))
* door tools for dynamical spots, CBED, CBED thickness and STEM images ([#918](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/918)) ([abff3a4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/abff3a4d2675fbff44de21abdc5f89a8c9413713))
* door tools for Index, the zone axis, the simulated spots and the Spots table ([#968](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/968)) ([0e7423d](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0e7423d41af933e33dcaeb6ade9056669aed9e64))
* door tools for the Simulation document and the crystal view ([#972](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/972)) ([04537b4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/04537b45cdcb4cc215393d6029307ae867c80f09))
* door tools for the Simulation document and the crystal view ([#994](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/994)) ([fedb83b](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/fedb83bb69f89913327a4ac578d82a9951a81353))
* double diffraction and the excitation error in the Diffraction room's Simulation section ([#883](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/883)) ([64116ba](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/64116ba1a8f7db9d8b68094c658cd16f0a7c4ea5))
* drag to tilt and rotate; solutions, Flip and Fit scale in the Index section ([#889](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/889)) ([e059109](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/e0591090a0ed6857e70430afb5a358db20de0779))
* dynamical spot intensities with a thickness slider ([#911](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/911)) ([abff3a4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/abff3a4d2675fbff44de21abdc5f89a8c9413713))
* EBSD Maps shows its results beside the map, with the map picker in its heading and the key on the map ([#1077](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1077)) ([11e0289](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/11e028902d260770672ed76b2ff9badc6c99e101))
* files and figures: methods records, HyperSpy files, vector figures and the size rule ([#952](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/952)) ([82fe5a2](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/82fe5a2f39dec5e8dafaaa9ef21ea8cf051c52dc))
* Find Phases takes its elements from EDS and searches the Materials Project ([#998](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/998)) ([02497f9](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/02497f9eab6b012dac3313ec8704f8a37f6fe94e))
* found spots are marks, and clicked spots give the zone axis ([#880](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/880)) ([c2cd9e8](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/c2cd9e8cdc3739ef81af69fb5f1ba2a2d906207e))
* Help opens the documentation, tutorials and feedback, and the welcome canvas offers Tutorials and New Simulation ([#991](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/991)) ([c7379a6](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/c7379a6f1ff0bd02cb7db8907a98dc8eac405d6d))
* HRTEM runs export as abTEM scripts, and an atom model opens as the specimen ([#975](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/975)) ([d265526](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/d26552639d0589882305d8313e57141da9561b28))
* HRTEM simulation: specimen, live image, optics, frozen phonons, door tools and Place Beside ([#965](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/965)) ([5e507d8](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/5e507d827f3db4aed09960707c87b65a17a4d509))
* Index finds the spots and the full orientation of a spot pattern ([#874](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/874)) ([140df35](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/140df35b9db092be1058fc0e21a175b48ba40065))
* keys to move between the rooms of a workspace ([#838](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/838)) ([e6b323c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/e6b323c4ab089b78aab2cd3e84abce9a7a901dc4))
* New Simulation document ([#920](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/920)) ([04131f5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/04131f55c6719d5963d5696d5bb98404f9f99444))
* New Simulation opens with the Add Phase sheet in front, and Cancel leaves an empty state with Add Phase… ([#987](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/987)) ([6030597](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/60305979a215b3eddcbb37655ccba6a8b80840e3))
* Quick Look for dm3, dm4, mrc, emd and ser files ([#974](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/974)) ([093b14f](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/093b14f370e8a240b95c41b1159413825ab84b02))
* simulated spots over a measured pattern for a typed zone axis ([#858](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/858)) ([37a6b78](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/37a6b782e43316736df5ea6bde58e33de062e341))
* spot table with hkl, expected d and misfit, and Spots CSV ([#881](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/881)) ([fde0bdd](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/fde0bdd46da6b30744d9f567a418ed46d71af580))
* STEM images with detector bands and frozen phonons ([#913](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/913)) ([abff3a4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/abff3a4d2675fbff44de21abdc5f89a8c9413713))
* strain maps from a lattice image ([#935](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/935)) ([5c58117](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/5c5811705270feed28286aa41f231bad778b7e23))
* the agent door lists how an agent reaches every control, has a workflow guide, and opens demo data ([#769](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/769)) ([83ee959](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/83ee959c62828c3198da98ce0765e41b27b0d814))
* the crystal pane follows the indexed orientation in the Diffraction room ([#910](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/910)) ([b70184e](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b70184eaa077d9e0bc37be7a5ef12c5542e5f9ef))
* the Crystal pane shows the simulated slab and marks atom columns on the image ([#976](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/976)) ([18ee740](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/18ee7405272e5f1e490355f2331511a540fd9869))
* the Diffraction room opens a pattern saved as PNG or JPEG ([#843](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/843)) ([ee2098c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/ee2098cc69dfd1c3364998e48fe9c436c24dbdab))
* the Diffraction room takes its phases from the Materials Project and your library ([#887](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/887)) ([000d672](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/000d67258d1bc1e380026e5d43bc65414e84ae0b))
* the EELS demo carries a core loss with C, N and O K edges, so the edge fit and its maps can be shown ([#1100](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1100)) ([3a5d483](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/3a5d48389d38a4f242155f1522743f52a95133b3))
* the EELS maps PNG draws a colour bar under each map ([#877](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/877)) ([17ca4d3](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/17ca4d3ba2a3ee7f1d827f021b29514e685157e3))
* the EELS room's CSVs and maps PNG carry their methods record ([#888](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/888)) ([1ea8f28](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/1ea8f28cdf181d50ab80ac96215f518cfde5b6e0))
* the FFT room reads the frequency under the pointer on the power spectrum ([#865](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/865)) ([789ecef](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/789ecef1fb0a4a28dc574237bba1a6746d28e147))
* the FFT room's transform PNG, radial profile and spots CSVs carry their methods record ([#879](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/879)) ([836fd0b](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/836fd0b117fcb5550048f4cc9c84b9588bb5790f))
* the Image room's PNG and CSV exports carry their methods record ([#871](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/871)) ([0ce25e6](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0ce25e6fa9ea11a591efd1162c6f9baf216ea046))
* the Indexing and Patterns rooms' PNG, CSV and .ang exports carry their methods record ([#873](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/873)) ([ed05d21](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/ed05d211646a889b5913714cca9c4c69b7215e4f))
* the Maps room's map, texture, grains and histogram exports carry their methods record ([#878](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/878)) ([cded1b6](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/cded1b61e9ae0fd87e3dc6938c795841ffd83803))
* the Particles CSV and the Diffraction readout CSV carry their methods record ([#882](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/882)) ([3bfd299](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/3bfd29940697433089549691b33b149e3f511850))
* the Spots table names a spot of double diffraction ([#969](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/969)) ([24eb5a5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/24eb5a564b3c4b18b103199fc2a8681901500413))
* the Tilt tool tilts from the keyboard and VoiceOver ([#950](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/950)) ([a3355e5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a3355e50509de74c60639860a06b99b71485215b))
* TIA .ser and .emi files open, images in the image rooms and spectra in the EDS or EELS room ([#909](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/909)) ([61e4aa5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/61e4aa58574b7a3455812cfab2832ce222e30109))
* two-beam CBED thickness ([#916](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/916)) ([abff3a4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/abff3a4d2675fbff44de21abdc5f89a8c9413713))


### Bug Fixes

* a CBED run frees each stretch's Metal buffers and shows its progress and Stop in the toolbar ([#1021](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1021)) ([dab7b12](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dab7b128b57bcc1af8e1ee38eaa56897ee5b6a92))
* a CBED run names its time before it starts, refuses one past 15 min, and defaults to 0.5 mrad per pixel ([#1081](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1081)) ([266a018](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/266a0180abf49b820c4ae5cbb5356787cd6b7745))
* a core-loss-only EELS spectrum image fits its edges and shows no t/λ ([#1073](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1073)) ([#1074](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1074)) ([2e93421](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/2e934218525f118aade0b27ee15336a1bc1e14f0))
* a local Release build launches, the embedded HDF5 frameworks are re-signed ([#1009](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1009)) ([fd44fb8](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/fd44fb813b353e7ffce3742bc2495cb9d97e288e))
* a poor CBED thickness fit shows its number greyed under the warning ([#1122](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1122)) ([e1e83c1](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/e1e83c16f0beadce8dafe58bc195ee94cc7369b5))
* a ring calibration fits the central background as py4DSTEM does (DiffractoKit 0.24.0) ([#1080](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1080)) ([7c7a3ec](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/7c7a3ec40675ba615240478edb35d31a21e58876))
* a Simulation document with no phase shown draws no Au, and the Si demo opens showing Si ([#1120](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1120)) ([db3960b](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/db3960b8dbac40ec38909a3e201c1502ac3eb8b8))
* a spot's verdict reads as plain words, its kit sentence as the tooltip ([b7d79fe](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b7d79fed2427a415436125fec618e303888ce85e))
* a STEM image before Simulate says "not computed yet: press Simulate", not "computing" ([#1022](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1022)) ([dab7b12](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dab7b128b57bcc1af8e1ee38eaa56897ee5b6a92))
* a TIA .ser opened alone asks once for its folder to read the .emi beside it ([#982](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/982)) ([a57d89e](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a57d89e767249b1f3613dc0f978adfc9507adb8e))
* a transfer-function spacing label that would overlap a stronger one's is left out ([#1098](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1098)) ([95b748b](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/95b748b780cc5ac839d75f5bb93f53a171cc8579))
* an atom model as the source refuses Dynamical, Fit Discs, CBED labels and Use in Simulation, and keys CBED, STEM and Dynamical runs ([#953](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/953)) ([47a3fb5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/47a3fb597df274e18b71a0f3015ba911a450f0c3))
* an atom model as the source refuses Dynamical, Fit Discs, CBED labels and Use in Simulation, and keys every run ([#980](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/980)) ([47a3fb5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/47a3fb597df274e18b71a0f3015ba911a450f0c3))
* an SEM spectrum's Quantify gives line intensities only, as exSpy does ([#1132](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1132)) ([63f7a21](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/63f7a21cb25f333e8c175b937f1aa7027d70daee))
* an update renames macEM.app to Electron Microscopy Studio.app ([#774](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/774)) ([0697ceb](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0697cebd3440bb16fc9febc6dd75148579053d93))
* **deps:** take FormatoKit 0.19.0 and EMSuiteUI 0.14.0; a HyperSpy spectrum saved as .hdf5 opens ([#869](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/869)) ([0d61023](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0d61023c233d8766056bf7d1e6b150a1873b9f60))
* EBSD band families read {200} {220} {311}, and the detector tiles over the pattern are named ([#1069](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1069)) ([b3d73e3](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b3d73e36e4ce8da18d71ac086f1d58a2a53c98a5))
* EBSD band families read {200} {220} {311}, and the detector tiles over the pattern are named ([#1071](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1071)) ([b3d73e3](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b3d73e36e4ce8da18d71ac086f1d58a2a53c98a5))
* Export starts closed in every room ([#859](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/859)) ([8bcf4ae](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8bcf4ae7372cd644ce390907d6be29fa0d70f2be))
* FFT, Diffraction and Maps sit on the shared two-panel centre, and their tables are bottom tabs ([#1103](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1103)) ([04004d7](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/04004d74cb3724953e2e7b970abf35a2fe37633d))
* How to Cite and Report a Problem leave the Window menu ([8db5c2c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8db5c2ca8a0478254f6fa7d1b328c21f2e1a555c))
* HRTEM images have square pixels (grid lengths follow the box's sides) ([#1011](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1011)) ([4198f57](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/4198f57086185e684f7dd69f4adf43b5fe88c78e))
* Index and the simulated spots wait for the specimen's phase; the calibration standard only calibrates ([#1146](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1146)) ([47763be](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/47763be3f3f8dd743c63611082497d93f444c464))
* Index on the nanowire demo finds GaAs, on a cleaner averaged pattern ([#1134](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1134)) ([4e36ac8](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/4e36ac8192d274d4f77bd4a9727facc96a5b5e6d))
* Maps says when the Indexing room has a run on the scan it shows, and offers it ([#1072](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1072)) ([cdf877b](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/cdf877b32007cbe3262bdde63fc8906e8e839b24))
* Measure Thickness finds the disc's centre on noisy recorded patterns ([#981](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/981)) ([b011fd5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b011fd5ea0c97b4d3d9d8ae6e2a850915de01525))
* moving to another room clears the status line of the room before ([#1093](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1093)) ([70c9848](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/70c98487899655ac949911d4aed9f38d5491a845))
* nine audit fixes for the agent door, folder grants, typed indices and image opening ([#958](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/958)) ([158e110](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/158e11040bb538499ffc314702cc596da4879498))
* no demo or thin-film defaults on a user's data in SEM-EDS, EBSD Dictionary and Hough, and Diffraction ([#1145](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1145)) ([aa7b96f](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/aa7b96fa1c55cae298e371821d683cfe6a199f65))
* release-please edits CITATION.cff's version line only, so the file keeps its quoting ([#1136](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1136)) ([6d363f0](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/6d363f05029dc38275a1e3e03d60737fa0e3a9d3))
* ring labels, the Diffraction header and agent status lines no longer cut text at the edge ([#1092](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1092)) ([8e81c7a](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8e81c7a6bdf767a1a1e40db77bc5af92264819e0))
* Settings &gt; Agents resolves the Agent folder's path off the main actor, and the folder walk can run off it ([#986](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/986)) ([34cbb93](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/34cbb931792fd56073e1a0152aba27c36902db26))
* ShellCrystal has its own object ids in the Xcode project ([#971](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/971)) ([b189cb8](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b189cb8025ac6dc63dcc1d6d842ceebf698bb32d))
* simulated CBED and STEM documents name the real image in the status line, a finished STEM run reports its positions ([#1010](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1010)) ([27e1128](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/27e11286bc1d245c14ed95841884f9ebf44d113c))
* simulated hkl labels are drawn only where they clear a stronger label and every other ring ([#1030](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1030)) ([dab7b12](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dab7b128b57bcc1af8e1ee38eaa56897ee5b6a92))
* the 2.6.0 walk findings (HOLZ beams, figure hkl, Find Phases elements, simulation annulus, door example, NBED spot finder) ([#1154](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1154)) ([d64e051](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/d64e051f2b91c5c53ff5f315cfac178bb8db3baf))
* the Au demo pattern opens in the Diffraction room, ready to calibrate ([b7d79fe](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b7d79fed2427a415436125fec618e303888ce85e))
* the CBED depth chip gives the pattern's size as width × height, as its header does ([#1033](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1033)) ([dab7b12](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dab7b128b57bcc1af8e1ee38eaa56897ee5b6a92))
* the crystal pane appears with the simulated spots; View &gt; Show Crystal is its only switch ([#967](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/967)) ([f27c4b5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/f27c4b5df88677b4801031b3c4e0490041c6aed1))
* the design review's clear fixes: alert default, one number format, switch rows, table headings, Log switches, simulated documents' sections ([#1049](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1049)) ([3d09781](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/3d09781c4e5b63cc5ee1e3f7baa380c2e618a104))
* the Diffraction room says In-plane rotation and q max, and writes every file from its Export section ([#992](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/992)) ([1192b5a](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/1192b5a6c3d627782ba4f0a7458390086ca64875))
* the door's diffraction picture is the pattern shown, with the room's display, rings and annulus ([#1012](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1012)) ([a79091d](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a79091d6f2d8c563fd1b3f079f4779bf7ccd62c1))
* the EELS demo fits at its defaults: no convolution with a low loss of another dispersion ([#1127](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1127)) ([dee2423](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dee242301dd324df2d9e9bc873cc9bd16795c00c))
* the Holder section takes the holder's β sense ([#1109](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1109)) ([cf673a5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/cf673a5f08e6b9f0919aaafa0a90ec8b80427555))
* the Index section says why Index is off ([b7d79fe](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b7d79fed2427a415436125fec618e303888ce85e))
* the nanowire demo pattern ships distortion-corrected with its scale, so Index runs without typing a number ([#1130](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1130)) ([0a828e6](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0a828e6c03c0bd1f1590c3ce8a4126c4a79dc463))
* the nanowire demo spot pattern lands in the Diffraction room ([#1099](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1099)) ([0cf9542](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/0cf9542f1baa3ba517806ce6e313e5a22558ec76))
* the Precipitate section drops the β″-in-Al literature example; takes EMSuiteUI 0.20.1 ([#1147](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1147)) ([9b4752d](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/9b4752d14244597fcdb17f8137ec9e92905a2062))
* the Precipitate section takes any phase and a typed relationship, β″ in Al only as a literature example ([#1138](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1138)) ([af0b64e](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/af0b64ed93a248be7a4256730573063c84b39d94))
* the Results room reports the EDS room's fit of an SEM spectrum, as line intensities ([#1129](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1129)) ([b1a5b42](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b1a5b42df9e6b3902d8e49545778eaf34b351773))
* the Results room's empty state names every room that sends results ([b7d79fe](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b7d79fed2427a415436125fec618e303888ce85e))
* the SEM-EDS demo's first Quantify gives at%, with Zr fitted on its L line ([8db5c2c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8db5c2ca8a0478254f6fa7d1b328c21f2e1a555c))
* the Simulation crystal view draws the slab no deeper than it is wide, so it fills the pane ([#1020](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1020)) ([dab7b12](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/dab7b128b57bcc1af8e1ee38eaa56897ee5b6a92))
* the Thickness part lists Phases and its refusal names the step still to take ([#1091](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1091)) ([88a8889](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/88a888918ab638eac040b32485d441b29a9e3aab))
* the welcome inspector never breaks a file extension across two lines ([8db5c2c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8db5c2ca8a0478254f6fa7d1b328c21f2e1a555c))
* the whole-app review's findings: bottom tabs, a Silicon demo on silicon, the Index result kept in the header, demos with structure ([#1116](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/1116)) ([090f7b2](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/090f7b28e1f96eb0a031c02d43feae380abd380e))
* variants, zone-axis families, powder phases and Find Phases warnings read without colour ([#990](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/990)) ([ec59131](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/ec591313bac251d5e8ec69a635e23bcb1151f2f6))
* VoiceOver reads the SEM databar switch by its row's words ([8db5c2c](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8db5c2ca8a0478254f6fa7d1b328c21f2e1a555c))


### Performance Improvements

* an EBSD bind makes the Maps document once for the Indexing and Maps rooms ([#929](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/929)) ([96f5b59](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/96f5b59171b36019d73fd22271ed08e7c566f038))
* an EBSD bind makes the Maps document once for the Indexing and Maps rooms ([#948](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/948)) ([96f5b59](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/96f5b59171b36019d73fd22271ed08e7c566f038))
* crystal maps keep their step sizes, ODF powers go through vForce, Hough voting drops its per-triangle arrays ([#770](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/770)) ([8655d2a](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/8655d2a1e97b51e18b85b2520a2d673d86599597))
* dictionary indexing multiplies on Metal Performance Shaders with its GPU buffers made once per run ([#773](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/773)) ([2c5cc9e](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/2c5cc9ed1e648364cf31cfdb00ae8b2ab126928d))
* keep whole-image Float copies off the main actor in Find Spots, spot clicks, Index and ring fits ([#945](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/945)) ([feefbf5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/feefbf5301b8de6b2515d7b868a80e6622eba0e0))
* NLPAR estimates its noise over the cores, and the pattern filters keep their FFT plans ([#870](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/870)) ([a55484a](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a55484a9ad91f812d03a9a986c287bef865ea86c))
* the Maps inspector reads the document's phase counts instead of counting the map on every pass ([#940](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/940)) ([010efb9](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/010efb99370a3504811322b6ba58c3c26e00ef7f))

## [2.1.1](https://github.com/EMSuite/Electron-Microscopy-Studio/compare/v2.1.0...v2.1.1) (2026-11-18)


### Features

* a large image's open shows its stage and time and can be stopped ([#752](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/752)) ([9b8dbf5](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/9b8dbf5c4715b969b2dcdec0c398656919bf93a3))


### Bug Fixes

* **deps:** a second EELS Align no longer holds an extra copy of the file, and Auto ID offers what it nearly found ([#757](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/757)) ([3836625](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/3836625cfb1881b752101ca467eb0a7981927c59))
* export and session sheets open on the window that asked, and one window's export no longer blocks another ([#751](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/751)) ([327f0d3](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/327f0d36ed899049d671b5fa2d66dd8dff657215))
* exported files name Electron Microscopy Studio as their writer ([#765](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/765)) ([9c6f697](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/9c6f697ecdef889a99d210d12a02706b58a41f7b))
* File &gt; Open with every window minimised opens no second, empty window ([#763](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/763)) ([2f1c3c4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/2f1c3c433b147a3b88a53d5b8f36d1dbfc0b22ce))
* refuse an image export above 16384 px from its size, before the full-size copy ([#750](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/750)) ([a946517](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/a946517a38738549bfd230429b79ecea0eb94f7e))
* the website download is named Electron Microscopy Studio, its app and DMG files included ([#760](https://github.com/EMSuite/Electron-Microscopy-Studio/issues/760)) ([b3aa3f4](https://github.com/EMSuite/Electron-Microscopy-Studio/commit/b3aa3f44ac413580bf02f1ea6f11f8db7c003210))

## [2.1.0](https://github.com/macEMSuite/macEM/compare/v2.0.2...v2.1.0) (2026-11-16)


### Features

* a Settings window with sections; Settings &gt; Images holds the SEM databar choice ([#720](https://github.com/macEMSuite/macEM/issues/720)) ([68043db](https://github.com/macEMSuite/macEM/commit/68043dbc705430022b5bfcfe844343a130c4ddc4))
* an optional zero-loss FWHM for EELS Fourier-ratio deconvolution ([#711](https://github.com/macEMSuite/macEM/issues/711)) ([b317077](https://github.com/macEMSuite/macEM/commit/b3170775e70e02d49141e3a1163693125b7405f9))
* Check for Updates in the website download (Sparkle) ([#708](https://github.com/macEMSuite/macEM/issues/708)) ([6be8dd4](https://github.com/macEMSuite/macEM/commit/6be8dd42ae10effc16e6cfe3e60dc3674beae4ca))
* Edit &gt; Undo for clearing the ring calibration and removing an EELS reference ([#722](https://github.com/macEMSuite/macEM/issues/722)) ([8a874c9](https://github.com/macEMSuite/macEM/commit/8a874c9f2909d8559161e76014d51afcc595d2a6))
* Edit &gt; Undo for removing FFT spots ([#717](https://github.com/macEMSuite/macEM/issues/717)) ([9fc0ea1](https://github.com/macEMSuite/macEM/commit/9fc0ea1e736890dbfddcff67219270c894a5dc93))
* Edit &gt; Undo puts back a removed Diffraction ring or spot ([#719](https://github.com/macEMSuite/macEM/issues/719)) ([6d84852](https://github.com/macEMSuite/macEM/commit/6d84852b55f9b73f999d8906dcff00ffa5278bdc))
* Edit &gt; Undo puts back a removed Image room mark ([#712](https://github.com/macEMSuite/macEM/issues/712)) ([07d5131](https://github.com/macEMSuite/macEM/commit/07d51318fbdc2b43ee84b93f5191d4c61b84d033))
* list only the current room's exports in the File menu ([#702](https://github.com/macEMSuite/macEM/issues/702)) ([53a56e0](https://github.com/macEMSuite/macEM/commit/53a56e0c9a3a34964b5357195a6ee460e9fbe0ac))
* marks and spots by keyboard and VoiceOver: ⌥-arrows, Return and a one-pixel step ([#736](https://github.com/macEMSuite/macEM/issues/736)) ([0e9a654](https://github.com/macEMSuite/macEM/commit/0e9a654016f91e11ec20e1798a460e503f18f5d3))
* name the App Store build Electron Microscopy Studio ([#745](https://github.com/macEMSuite/macEM/issues/745)) ([a9ceb8e](https://github.com/macEMSuite/macEM/commit/a9ceb8e7d249cb1124fa035f6b04a32f74b014b4))
* Particles can analyse a region drawn on the image, and say when a render's burnt-in labels are found as objects ([#735](https://github.com/macEMSuite/macEM/issues/735)) ([793bed0](https://github.com/macEMSuite/macEM/commit/793bed022525b01667dbbe112ba53e07751bfa94))
* Settings &gt; Images chooses what the scroll wheel does on a picture: Zoom or Pan ([#732](https://github.com/macEMSuite/macEM/issues/732)) ([9c7603a](https://github.com/macEMSuite/macEM/commit/9c7603ac0788b16d132110312a144fb3ca10e036))
* the agent door's first tools that act (room, EDS picks and runs, EDS maps picture) ([#709](https://github.com/macEMSuite/macEM/issues/709)) ([f7d7193](https://github.com/macEMSuite/macEM/commit/f7d7193a45d897a08e0ca97f4ff472df919ed531))
* the FFT transform PNG can be exported as shown, resampled to the room's shape ([#734](https://github.com/macEMSuite/macEM/issues/734)) ([0e917ff](https://github.com/macEMSuite/macEM/commit/0e917ffde5e4bc40085de5d18a3a99b88e91f704))


### Bug Fixes

* a background launch that came up with no window opens one ([#729](https://github.com/macEMSuite/macEM/issues/729)) ([142b31f](https://github.com/macEMSuite/macEM/commit/142b31f7a5acbbf6faf83d9db9cbf55cb8983bf1))
* a cancelled texture stops between its figures instead of holding a closed map; the image rooms' memory check settles ([#716](https://github.com/macEMSuite/macEM/issues/716)) ([2bdf257](https://github.com/macEMSuite/macEM/commit/2bdf2572549de961378a94c51617f9e3b3ed4cbb))
* a stack frame keeps the bit depth of its file ([#678](https://github.com/macEMSuite/macEM/issues/678)) ([cd770f6](https://github.com/macEMSuite/macEM/commit/cd770f6b87f2e3f89380426ab42ef7de3f95175f))
* a stopped or superseded run ends before the next one starts, and never lands ([#688](https://github.com/macEMSuite/macEM/issues/688)) ([55f77b9](https://github.com/macEMSuite/macEM/commit/55f77b9152d17bb701248353365c8e184c577ee0))
* a Velox EELS cube holds its counts as Floats where the file's values are exact in Float32 ([#677](https://github.com/macEMSuite/macEM/issues/677)) ([107b5f2](https://github.com/macEMSuite/macEM/commit/107b5f2acef5cbe724eea5ea2b78a6ca4fe4a88d))
* an EBSD master pattern stays at its file's bit depth, so a uint8 one takes a quarter of the memory ([#682](https://github.com/macEMSuite/macEM/issues/682)) ([3650de3](https://github.com/macEMSuite/macEM/commit/3650de33ce729e04b39a47f36c610cec9a6295fb))
* an image keeps the bit depth of its file, and an 8- or 16-bit image is drawn as stored ([#676](https://github.com/macEMSuite/macEM/issues/676)) ([6c1eef6](https://github.com/macEMSuite/macEM/commit/6c1eef6e1b5ca0efe5951c3a39b71f65e39393ae))
* Bruker, EDAX and EMsoft .h5 maps without patterns open in the Maps room ([#737](https://github.com/macEMSuite/macEM/issues/737)) ([5c8d8f1](https://github.com/macEMSuite/macEM/commit/5c8d8f1a4fa8cba3fb44dcaa5584ab237775f442))
* carry the lattice unit from the file to the Kikuchi overlay instead of guessing it ([#657](https://github.com/macEMSuite/macEM/issues/657)) ([b91d1a4](https://github.com/macEMSuite/macEM/commit/b91d1a405a008722b9814d49162e0b651ee0fd8b))
* centre the ZLP shift tile on its flat bulk so far pixels on one side do not paint it solid ([#655](https://github.com/macEMSuite/macEM/issues/655)) ([542c8f8](https://github.com/macEMSuite/macEM/commit/542c8f89aa299cc109386b8039aa18f1df45056a))
* closing a file cancels its running FFT jobs, so their image goes without waiting ([#669](https://github.com/macEMSuite/macEM/issues/669)) ([4d20f69](https://github.com/macEMSuite/macEM/commit/4d20f6989115b818ed3c30f4c223db48257b48a7))
* closing a file cancels its running particle analysis, which stops between stages ([#675](https://github.com/macEMSuite/macEM/issues/675)) ([2e7c514](https://github.com/macEMSuite/macEM/commit/2e7c514756bfcd033056cc22d682c19354fe88a5))
* closing a file, a window or a room lets go of every canvas and mask it held ([#668](https://github.com/macEMSuite/macEM/issues/668)) ([35a5738](https://github.com/macEMSuite/macEM/commit/35a5738a9af02c1b8d5912ed24b72e4558c3dec5))
* damaged EDS and EBSD files are refused in words, and one flat pattern no longer stops a run ([#648](https://github.com/macEMSuite/macEM/issues/648)) ([ebc6177](https://github.com/macEMSuite/macEM/commit/ebc6177671bdb08f0c753a54a7ebe70d0c0d06bb))
* demo files are replaced atomically and a damaged sidecar never reaches a force-unwrap ([#649](https://github.com/macEMSuite/macEM/issues/649)) ([ab24ff8](https://github.com/macEMSuite/macEM/commit/ab24ff8be059b2b8b4b06464d789a5399b673c4d))
* **deps:** SpectroKit 0.14.3; results change: EDS absorption correction for a GMS file takes the tilt from the file's Stage Alpha and Beta, as exSpy does, so a tilted GMS file's quantified composition differs from 2.0.2 ([27224a1](https://github.com/macEMSuite/macEM/commit/27224a15490bed24776079e84a934e9e08e9126c))
* **deps:** take MacEMUI 0.12.3, so the store build's agent door names its server with a space in the app name ([ca2d887](https://github.com/macEMSuite/macEM/commit/ca2d887499d0a5802027037f840c0efff2258fe8))
* **deps:** take MacEMUI 0.12.3, so the store build's agent door works with a space in the app name ([#747](https://github.com/macEMSuite/macEM/issues/747)) ([ca2d887](https://github.com/macEMSuite/macEM/commit/ca2d887499d0a5802027037f840c0efff2258fe8))
* dictionary indexing and refinement hold a block of patterns at its stored bit depth ([#684](https://github.com/macEMSuite/macEM/issues/684)) ([6568e8e](https://github.com/macEMSuite/macEM/commit/6568e8e252a1796724bf2d3c3eb50ee35a732cf0))
* dictionary matches, orientation samples and pole figures stay within a stated size ([#671](https://github.com/macEMSuite/macEM/issues/671)) ([96faf2d](https://github.com/macEMSuite/macEM/commit/96faf2df9fd188fc80c5d56c012ba28f00cefd69))
* drop a ring fit when the diffraction centre moves while it runs ([bd09a98](https://github.com/macEMSuite/macEM/commit/bd09a981d703e8aa9c975b22173f9b304ccf47ab))
* EELS references take their edge from a row and From Region is a plain button ([#714](https://github.com/macEMSuite/macEM/issues/714)) ([51773f3](https://github.com/macEMSuite/macEM/commit/51773f3aed75298aa345497418b66c30cac06548))
* exports, a refitted deconvolution, colour maps and overlay masters no longer hold memory after their use ([#670](https://github.com/macEMSuite/macEM/issues/670)) ([3ebb434](https://github.com/macEMSuite/macEM/commit/3ebb434639cc77e939f3c68c416a150baccf140b))
* grain areas and the lineal intercept use both scan steps; results change: on a map whose x and y steps differ, grain areas, the mean lineal intercept and the ASTM grain size number differ from 2.0.2 ([1d6792b](https://github.com/macEMSuite/macEM/commit/1d6792ba0259b345a57a607515c14f14945d3a2c))
* keep the IPF key's corner labels off the triangle in the Maps Key tab ([#728](https://github.com/macEMSuite/macEM/issues/728)) ([e3fd0a3](https://github.com/macEMSuite/macEM/commit/e3fd0a345794d2056b01ae893a15a44607b298e1))
* make the quality maps from the processed scan once a Process run has landed; results change: after a Process run, the Image quality and Average dot product maps are of the processed patterns, not the stored ones as in 2.0.2 ([1f83a65](https://github.com/macEMSuite/macEM/commit/1f83a65a538b70b58cd302ddfa64fd726fb40bba))
* Maps tabs full width, tiles and reference rows as buttons, departures named ([#724](https://github.com/macEMSuite/macEM/issues/724)) ([f34d8a9](https://github.com/macEMSuite/macEM/commit/f34d8a9a8247e7865909e1c6689ca1ffc2c81dc7))
* NaN, zero and degenerate inputs in SEM indexing never crash or hang ([#646](https://github.com/macEMSuite/macEM/issues/646)) ([62a37ff](https://github.com/macEMSuite/macEM/commit/62a37ff4b591a5eef3782905812d7552a4141714))
* no force-unwrap or try! can trap on a damaged file; the audit fails on a new one ([#662](https://github.com/macEMSuite/macEM/issues/662)) ([ec71df5](https://github.com/macEMSuite/macEM/commit/ec71df561f1219a5a78335dba4fc327c87e41030))
* no inspector view holds a file's pixels, and a test fails one that does ([#673](https://github.com/macEMSuite/macEM/issues/673)) ([963ef78](https://github.com/macEMSuite/macEM/commit/963ef78e0d70aefd07679e83a37acc9ad3e4bf03))
* pair a monoclinic m phase in Compare and sample the ODF without column aliasing ([#654](https://github.com/macEMSuite/macEM/issues/654)) ([06f844c](https://github.com/macEMSuite/macEM/commit/06f844ca258f13166d5329ddb4a00543d1762329))
* pane hairlines use the system separator, so they show in light mode ([#710](https://github.com/macEMSuite/macEM/issues/710)) ([b337136](https://github.com/macEMSuite/macEM/commit/b337136fc7ba29afdfe904a22e157c2cedf9411a))
* reading an .ang map leaves malloc nothing to keep after the map closes ([#731](https://github.com/macEMSuite/macEM/issues/731)) ([b50c5e8](https://github.com/macEMSuite/macEM/commit/b50c5e8208aacacae2c4f9b8098ab319403c4c58))
* refuse the GND density on a map whose step is in no length unit ([#652](https://github.com/macEMSuite/macEM/issues/652)) ([54277c9](https://github.com/macEMSuite/macEM/commit/54277c9cdd367461f05b29bacb3054d0f04ce3db))
* say when the projection centre, pixel size or sample tilt is assumed rather than read from the file ([#658](https://github.com/macEMSuite/macEM/issues/658)) ([584d817](https://github.com/macEMSuite/macEM/commit/584d817875a19f0e428cdaf706f93badeefb37e0))
* tell a refused access by its code and show failed EBSD passes in an alert ([#704](https://github.com/macEMSuite/macEM/issues/704)) ([4db0e20](https://github.com/macEMSuite/macEM/commit/4db0e2097b6843684c8d2597b0c5a302e31a2e07))
* the Diffraction room draws a pattern on a log scale from the file's own pixels ([#681](https://github.com/macEMSuite/macEM/issues/681)) ([0578aa3](https://github.com/macEMSuite/macEM/commit/0578aa377a9ca3e4232bc7cd88c53e6a23aa4462))
* the EDS room's own Open goes through the app's Open ([#705](https://github.com/macEMSuite/macEM/issues/705)) ([bb38c7a](https://github.com/macEMSuite/macEM/commit/bb38c7a45a6993dd9b3d9723adc406bf2e87b58b))
* the FFT room's View picker is the Display section's first row, not a control in the pane header ([#715](https://github.com/macEMSuite/macEM/issues/715)) ([53b3ee7](https://github.com/macEMSuite/macEM/commit/53b3ee707dc99262baa8f337a4ed6ff4f56ad777))
* the FFT spectrum on a large image peaks at two thirds of the memory it took ([#741](https://github.com/macEMSuite/macEM/issues/741)) ([54836a7](https://github.com/macEMSuite/macEM/commit/54836a7a10f56041b098514bb14dbc787a64125a))
* the store build's menu bar reads Microscopy Studio ([#748](https://github.com/macEMSuite/macEM/issues/748)) ([6482b4c](https://github.com/macEMSuite/macEM/commit/6482b4c14a8b5555df84adbdedc56402a9c504a9))
* the store build's menu bar reads Microscopy Studio, as Version.xcconfig asks ([6482b4c](https://github.com/macEMSuite/macEM/commit/6482b4c14a8b5555df84adbdedc56402a9c504a9))
* write the known acquisition values into .ang and .ctf and name the build in every SEM export ([#656](https://github.com/macEMSuite/macEM/issues/656)) ([0311e83](https://github.com/macEMSuite/macEM/commit/0311e830ed8741b9b998f008df765995e3dc1cb0))


### Performance Improvements

* build the Indexing results rows off the main actor ([#701](https://github.com/macEMSuite/macEM/issues/701)) ([5e6d6e9](https://github.com/macEMSuite/macEM/commit/5e6d6e9f897663fb3c3f8052e0608d81ec5567fd))
* build the particle ellipses and table rows once per change ([#697](https://github.com/macEMSuite/macEM/issues/697)) ([0cb2eba](https://github.com/macEMSuite/macEM/commit/0cb2ebad7fed54a70a360f8681cb54431f830fcf))
* count a dragged mark's lineage bytes from the replaced node ([#698](https://github.com/macEMSuite/macEM/issues/698)) ([e45ae82](https://github.com/macEMSuite/macEM/commit/e45ae8253ffbdb2ff1dbd614101c1ed1ece6cc66))
* draw the Maps room's figures off the main actor ([#695](https://github.com/macEMSuite/macEM/issues/695)) ([89fc4cc](https://github.com/macEMSuite/macEM/commit/89fc4cca0ec459d7598d5e9619499f61c3a716e8))
* encode the Patterns room's export pictures off the main actor ([#694](https://github.com/macEMSuite/macEM/issues/694)) ([f43cc82](https://github.com/macEMSuite/macEM/commit/f43cc82e9a93a4cb375329f3b59aebb445ff45cd))
* keep the EELS background previews per spectrum and windows ([#699](https://github.com/macEMSuite/macEM/issues/699)) ([aa8a140](https://github.com/macEMSuite/macEM/commit/aa8a1408f3211ff4c4c4b2ce428d64089cc7f205))
* make the Indexing room's export bytes off the main actor ([#693](https://github.com/macEMSuite/macEM/issues/693)) ([853f47f](https://github.com/macEMSuite/macEM/commit/853f47f8388eb97c2b598f4f720a4e2a30491372))
* run FFT Find Spots off the main actor ([#700](https://github.com/macEMSuite/macEM/issues/700)) ([95d6cfb](https://github.com/macEMSuite/macEM/commit/95d6cfb17e4bfb76eab928a606e861d3b1c220ad))
* set and write the SEM session report off the main actor ([#696](https://github.com/macEMSuite/macEM/issues/696)) ([7d56739](https://github.com/macEMSuite/macEM/commit/7d567393f6b1c2c57978814c80a943de32263ab2))
* the agent door's get_image draws the picture at the asked size and encodes it once ([#733](https://github.com/macEMSuite/macEM/issues/733)) ([00ad87f](https://github.com/macEMSuite/macEM/commit/00ad87ff1b060ba47de09d13140b69328dcf0d48))
* the FFT room draws its spectrum from 16-bit levels, half the memory ([#685](https://github.com/macEMSuite/macEM/issues/685)) ([c23cca2](https://github.com/macEMSuite/macEM/commit/c23cca2c079dd1ba17e5360267f751b6937572c2))
* the Indexing room draws its map off the main actor and keeps its counts as rows land ([#692](https://github.com/macEMSuite/macEM/issues/692)) ([f04ed45](https://github.com/macEMSuite/macEM/commit/f04ed45169f41d56791d5ecbe8c16d7d220218df))
* the Maps and Patterns views read numbers and pictures made once instead of on every draw ([#690](https://github.com/macEMSuite/macEM/issues/690)) ([812b776](https://github.com/macEMSuite/macEM/commit/812b776e42e642e7e6a74c740245e2095b844bae))
* the Patterns room makes its map, tile, mix and pattern canvases off the main actor ([#689](https://github.com/macEMSuite/macEM/issues/689)) ([7453e03](https://github.com/macEMSuite/macEM/commit/7453e03e25cb4fcb251a3eb1a21a7708bf9f91cc))

## [2.0.2](https://github.com/mac4DSTEM/macTEM/compare/v2.0.1...v2.0.2) (2026-11-12)


### Bug Fixes

* a slip-plane row names its trace's colour, and the Maps overlay speaks its colours ([#568](https://github.com/mac4DSTEM/macTEM/issues/568)) ([b7ec490](https://github.com/mac4DSTEM/macTEM/commit/b7ec490f083920b752e9bfca3074a5d0f0195cab))
* release files, cubes and canvases when no longer shown (memory for 2.0.2) ([#582](https://github.com/mac4DSTEM/macTEM/issues/582)) ([3021de6](https://github.com/mac4DSTEM/macTEM/commit/3021de697ef16b5e271116537663992bcde7b4e6))
* slip traces past DefDAP's colour list take its last colour, not black ([#575](https://github.com/mac4DSTEM/macTEM/issues/575)) ([acab31f](https://github.com/mac4DSTEM/macTEM/commit/acab31ff7ce251dd2e84738fa04535960dcec819))
* VoiceOver hears the scan point's values, the Maps histogram and the IPF keys' colours ([#565](https://github.com/mac4DSTEM/macTEM/issues/565)) ([3469aa3](https://github.com/mac4DSTEM/macTEM/commit/3469aa32b52a511a153d12c81052d2ecf03cc7b3))

## [2.0.1](https://github.com/mac4DSTEM/macTEM/compare/v2.0.0...v2.0.1) (2026-11-12)


### Bug Fixes

* a .ctf phase of Laue group 10 reads as point group m-3, not orix's unknown "m3" ([#545](https://github.com/mac4DSTEM/macTEM/issues/545)) ([b89d459](https://github.com/mac4DSTEM/macTEM/commit/b89d459297b508696f47f02a12c5558b7139bd33))
* a .ctf saved on Windows opens, and scan and map sizes read width × height ([#519](https://github.com/mac4DSTEM/macTEM/issues/519)) ([1f6fbfa](https://github.com/mac4DSTEM/macTEM/commit/1f6fbfa0e1e4b605996c7cc2dff0a96f58a982ed))
* a colour TIFF as GMS exports a displayed image opens as grey instead of being refused ([#550](https://github.com/mac4DSTEM/macTEM/issues/550)) ([3eb7fd1](https://github.com/mac4DSTEM/macTEM/commit/3eb7fd10d54a488c9a466c19e329ff748254acb8))
* a DM file with no 2D image says what it holds in words, not dimension tuples ([#543](https://github.com/mac4DSTEM/macTEM/issues/543)) ([5f65d82](https://github.com/mac4DSTEM/macTEM/commit/5f65d8269648e54cf23006b1043fbb8abf043054))
* a DM4 spectrum image with picked spectra no longer also raises a can't-open alert ([#554](https://github.com/mac4DSTEM/macTEM/issues/554)) ([afc5e19](https://github.com/mac4DSTEM/macTEM/commit/afc5e1942c0be7a7e2af5784be83f9f4c271bf7f))
* a file macEM cannot open is titled "macEM can't open this file", not "Something went wrong" ([#552](https://github.com/mac4DSTEM/macTEM/issues/552)) ([559dca8](https://github.com/mac4DSTEM/macTEM/commit/559dca81d1deacfc72b8a607428044a1b99271ca))
* a HyperSpy file that is not one spectrum is refused naming the file, not HyperSpy's __unnamed__ group ([#544](https://github.com/mac4DSTEM/macTEM/issues/544)) ([b6a51fd](https://github.com/mac4DSTEM/macTEM/commit/b6a51fd6689bdf1fb23a6ddb2b8f8c1f449ec0b5))
* a map-only Oxford .h5oina opens in the Maps room ([#516](https://github.com/mac4DSTEM/macTEM/issues/516)) ([833bcf3](https://github.com/mac4DSTEM/macTEM/commit/833bcf33eb4edb8b99dfed1b6bdd638119a537fa))
* a pattern's size reads width × height in Info and in the processing refusals ([#547](https://github.com/mac4DSTEM/macTEM/issues/547)) ([b4028a7](https://github.com/mac4DSTEM/macTEM/commit/b4028a717a637ad94f324e93e5260afb5e6d0c36))
* a TIFF macEM cannot read is refused in a sentence that names the file and the compression in words ([#534](https://github.com/mac4DSTEM/macTEM/issues/534)) ([0d7097b](https://github.com/mac4DSTEM/macTEM/commit/0d7097b1c25c00584e25c392df3ae8d1f9ea5588))
* an EELS line scan is refused once and no longer also opens as a grey image ([#560](https://github.com/mac4DSTEM/macTEM/issues/560)) ([9d813d0](https://github.com/mac4DSTEM/macTEM/commit/9d813d0f8ac152ba87f3d3278e4eba4f04955798)), closes [#559](https://github.com/mac4DSTEM/macTEM/issues/559)
* EBSD HDF5 files without patterns go to the Maps room or are refused in words that name them ([#528](https://github.com/mac4DSTEM/macTEM/issues/528)) ([7c44c77](https://github.com/mac4DSTEM/macTEM/commit/7c44c77dfda6cef17f26127293f2747ce50f9ac5))
* export panels suggest no folder for the on-disk demo files ([#549](https://github.com/mac4DSTEM/macTEM/issues/549)) ([c7eb1fe](https://github.com/mac4DSTEM/macTEM/commit/c7eb1feaa91b0bc612a590e27bca042f33b6e7a7)), closes [#507](https://github.com/mac4DSTEM/macTEM/issues/507)
* LZW-compressed TIFFs open (FormatoKit 0.15.0) ([#537](https://github.com/mac4DSTEM/macTEM/issues/537)) ([1db1944](https://github.com/mac4DSTEM/macTEM/commit/1db19446ad7dcfa5072fee7d8565603764b72e2f))
* the .ctf map's format names its writer in words, and a pattern file's own map keeps the Patterns line ([#548](https://github.com/mac4DSTEM/macTEM/issues/548)) ([631b583](https://github.com/mac4DSTEM/macTEM/commit/631b583e9e519f78a1e3871a58f6fe21f9071e35))
* the CTF map's format names its writer in words, and a pattern file's own map keeps the Patterns line ([631b583](https://github.com/mac4DSTEM/macTEM/commit/631b583e9e519f78a1e3871a58f6fe21f9071e35)), closes [#522](https://github.com/mac4DSTEM/macTEM/issues/522)
* the Maps grains CSV quotes a phase name with a quote, one IPF key image builder, and one unused Indexing property gone ([#498](https://github.com/mac4DSTEM/macTEM/issues/498)) ([1feb50b](https://github.com/mac4DSTEM/macTEM/commit/1feb50b87f55c6f7251e801a1f1224d72e925b8c))
* the Maps room's Euler row names the H5OINA convention for an H5OINA with patterns, not orix ([#546](https://github.com/mac4DSTEM/macTEM/issues/546)) ([9b23296](https://github.com/mac4DSTEM/macTEM/commit/9b232965c51a812ef39185a4b6038a1542729e75))
* the six SEM picture panes have the VoiceOver zoom actions their hint promises ([#557](https://github.com/mac4DSTEM/macTEM/issues/557)) ([922cbb8](https://github.com/mac4DSTEM/macTEM/commit/922cbb868cea55a6b0810b83066cd6fa0dcef56c))

## [2.0.0](https://github.com/mac4DSTEM/macTEM/compare/v1.3.0...v2.0.0) (2026-11-11)


### ⚠ BREAKING CHANGES

* macTEM is now macEM. The download is macEM.dmg and the app is macEM.app, which does not replace macTEM.app. To update: quit macTEM, open the DMG and drag macEM to Applications, then move macTEM to the Trash and replace its Dock icon. Recent files, Reopen Last Session, the folders you allowed, window positions and every .mactem.h5 session file carry over. Exports now name macEM: CSV first lines read "# macEM ...", the line profile's header key "shown in macTEM as" is now "shown in macEM as", and PNG Software, ANG OPERATOR, CTF Author, the MSA comment and the method JSON's "software" say macEM. Session files keep the .mactem.h5 name.
* every EBSD reader hands its orientation map over as CrystalMap ([#182](https://github.com/mac4DSTEM/macTEM/issues/182))

### Features

* a second opened file comes up as a tab of its own, like Finder and Safari ([#435](https://github.com/mac4DSTEM/macTEM/issues/435)) ([025c0cc](https://github.com/mac4DSTEM/macTEM/commit/025c0ccf56bb088da591f057a594b0a6f6c04eee))
* agent door: Claude and other agents on this Mac look at macTEM's windows over MCP ([#497](https://github.com/mac4DSTEM/macTEM/issues/497)) ([7489799](https://github.com/mac4DSTEM/macTEM/commit/74897997eda41a570acb439e64a21a3f05c6d3d0))
* an SEM spectrum goes through the shared EDS room's own Quantify, with the file's elements picked on open ([#401](https://github.com/mac4DSTEM/macTEM/issues/401)) ([e38f563](https://github.com/mac4DSTEM/macTEM/commit/e38f5636378225065b95e8f4bb4263ceb11ec474))
* complete the Maps room with grains, KAM, GOS, GND, slip and texture ([#238](https://github.com/mac4DSTEM/macTEM/issues/238)) ([fb04c32](https://github.com/mac4DSTEM/macTEM/commit/fb04c3252dc2291347864f0c1723b562519ab6dd))
* crystal map model and the neighbour misorientation histogram (figure F7) against orix ([#167](https://github.com/mac4DSTEM/macTEM/issues/167)) ([5904d76](https://github.com/mac4DSTEM/macTEM/commit/5904d762371892b937255731b93f827781f9736e))
* denoise EBSD patterns with NLPAR as pyebsdindex does ([#156](https://github.com/mac4DSTEM/macTEM/issues/156)) ([157047d](https://github.com/mac4DSTEM/macTEM/commit/157047d10c862739cb0b0c821963c580c86a7e1c))
* denoise the scan with NLPAR as the last Process stage in the Patterns room ([#194](https://github.com/mac4DSTEM/macTEM/issues/194)) ([1d90c28](https://github.com/mac4DSTEM/macTEM/commit/1d90c28d3136d1c20aeb077a65edc68999335143))
* each room lists what its verb waits for in a Requirements section, as mac4DSTEM does ([#397](https://github.com/mac4DSTEM/macTEM/issues/397)) ([b7be9f2](https://github.com/mac4DSTEM/macTEM/commit/b7be9f2576a407eebfdb77c8a648fe7f85dc3084))
* each window has its own files, and macOS's window tabs work (New Window ⌘N) ([#413](https://github.com/mac4DSTEM/macTEM/issues/413)) ([9bb692b](https://github.com/mac4DSTEM/macTEM/commit/9bb692b40e10d7d215329a1becbb06fc52eb9b7a))
* EBSD and TKD detector geometry and the moving-screen projection centre against kikuchipy (figure F5) ([#152](https://github.com/mac4DSTEM/macTEM/issues/152)) ([94db1d5](https://github.com/mac4DSTEM/macTEM/commit/94db1d5a00d02f060f1f3a2396cfe806df196ed8))
* every EBSD reader hands its orientation map over as CrystalMap ([#182](https://github.com/mac4DSTEM/macTEM/issues/182)) ([7bbbea0](https://github.com/mac4DSTEM/macTEM/commit/7bbbea0e3bda6ee8243113726801e213d53c1b2f))
* File &gt; Open Recent, Reopen Last Session and Workspace &gt; Run (⌘R), and Close, Stop and Show Output act on what the room shows ([#403](https://github.com/mac4DSTEM/macTEM/issues/403)) ([e076b72](https://github.com/mac4DSTEM/macTEM/commit/e076b729b22db1817e968b3d9bc60706f835206b))
* filter EBSD patterns in the Patterns room: Equalise, FFT filter and Average neighbours ([#206](https://github.com/mac4DSTEM/macTEM/issues/206)) ([0d1d06a](https://github.com/mac4DSTEM/macTEM/commit/0d1d06a37b80abea76d2671fd3ff568451805da8))
* filter EBSD patterns: FFT filters, CLAHE and neighbour averaging as kikuchipy does ([#158](https://github.com/mac4DSTEM/macTEM/issues/158)) ([8acb82e](https://github.com/mac4DSTEM/macTEM/commit/8acb82e68d3fc7b9943769fb17922b2ac7d49bbf))
* geometrical Kikuchi overlay and kinematic master pattern as kikuchipy does (figure F14) ([#203](https://github.com/mac4DSTEM/macTEM/issues/203)) ([343c9e6](https://github.com/mac4DSTEM/macTEM/commit/343c9e62e9abce1ecd49e8f45b36c799a81fdf0d))
* grain statistics and texture as Results rows and session report parts ([#248](https://github.com/mac4DSTEM/macTEM/issues/248)) ([c7bf884](https://github.com/mac4DSTEM/macTEM/commit/c7bf8844b415e83c0842b226c244fad1dad04971))
* grains, boundaries, neighbour network, KAM, GROD and GOS of EBSD maps against DefDAP 1.3.1 (figures F11, F12) ([#187](https://github.com/mac4DSTEM/macTEM/issues/187)) ([5f320aa](https://github.com/mac4DSTEM/macTEM/commit/5f320aa0528a9d9dcb5b95408878ed37cf98a08a))
* hand the Hough-indexed scan over as a CrystalMap as kikuchipy does ([#207](https://github.com/mac4DSTEM/macTEM/issues/207)) ([20897ee](https://github.com/mac4DSTEM/macTEM/commit/20897eefff37c9c8c8ba7d774f4437ff8819f84b))
* Hough indexing (Radon band detection, triplet voting, QUEST) against pyEBSDindex (figure F8) ([#178](https://github.com/mac4DSTEM/macTEM/issues/178)) ([d37ae00](https://github.com/mac4DSTEM/macTEM/commit/d37ae00feafc0ed143802d0d429c65ecbf9933b8))
* image quality and average dot product maps in the Patterns room's Map picker (figure F3) ([#191](https://github.com/mac4DSTEM/macTEM/issues/191)) ([41dcc4e](https://github.com/mac4DSTEM/macTEM/commit/41dcc4e87694fcf5a3fc2375a302e737f9a4983f))
* image quality and average neighbour dot product maps of EBSD scans (figure F3) ([#150](https://github.com/mac4DSTEM/macTEM/issues/150)) ([895f943](https://github.com/mac4DSTEM/macTEM/commit/895f943cd4799883d64823b65691306bcb195201))
* index EBSD scans against a master-pattern dictionary as kikuchipy does (figure F9) ([#181](https://github.com/mac4DSTEM/macTEM/issues/181)) ([6e4a185](https://github.com/mac4DSTEM/macTEM/commit/6e4a1856730f6ebc9cff97e82ddeb251e04b96a6))
* Indexing room (⌘7): Hough-index the scan, watch the IPF map grow, read each point's solution and bands ([#209](https://github.com/mac4DSTEM/macTEM/issues/209)) ([c88200b](https://github.com/mac4DSTEM/macTEM/commit/c88200bd5eb89c79f681cef0557814b474367f2b))
* Indexing room compares two results (Hough, Dictionary, the file's indexing) as linked maps and a disorientation histogram ([#245](https://github.com/mac4DSTEM/macTEM/issues/245)) ([8941a3e](https://github.com/mac4DSTEM/macTEM/commit/8941a3e7d0a79f31de2b9835db9aa8d9a90b8434))
* Indexing room indexes several phases by dictionary, merged as kikuchipy's merge_crystal_maps ([#247](https://github.com/mac4DSTEM/macTEM/issues/247)) ([90b5197](https://github.com/mac4DSTEM/macTEM/commit/90b519713e4bd591d3e5cb285df569f08e881d61))
* Indexing room: index with a dictionary against a master pattern, with Score and OSM layers and each point's best match, as kikuchipy does (figure F9) ([#227](https://github.com/mac4DSTEM/macTEM/issues/227)) ([1ef16a9](https://github.com/mac4DSTEM/macTEM/commit/1ef16a9426f1e757ffade4df0f335322b6e25c55))
* Indexing room: scalar layers through the Map Display, an Euler layer, and ⌘C copies the Results table as TSV ([#240](https://github.com/mac4DSTEM/macTEM/issues/240)) ([ce01882](https://github.com/mac4DSTEM/macTEM/commit/ce018825398d77340c04687e1a54a6d0a26b7073))
* **indexing:** Refine stage after Dictionary (orientation, PC or both) ([#437](https://github.com/mac4DSTEM/macTEM/issues/437)) ([ffddb6b](https://github.com/mac4DSTEM/macTEM/commit/ffddb6b44bd256a599865d72d59aba3187212ae2))
* Kikuchi overlay band edges at the Bragg angle, and overlay CSV and PNG export ([#228](https://github.com/mac4DSTEM/macTEM/issues/228)) ([07d2c06](https://github.com/mac4DSTEM/macTEM/commit/07d2c0634dba0220a123357cf6e52b4111bb94f5))
* Kikuchi overlay of the run's solution in the Indexing room's pattern pane ([#243](https://github.com/mac4DSTEM/macTEM/issues/243)) ([db594eb](https://github.com/mac4DSTEM/macTEM/commit/db594ebe1adbf0e4fa23414c55c2cc81cf8f477e))
* Kinematical Kikuchi overlay with Blend and the kinematical master pattern ([#236](https://github.com/mac4DSTEM/macTEM/issues/236)) ([d145c77](https://github.com/mac4DSTEM/macTEM/commit/d145c772eea3da08c36512442544d1b99c63653d))
* macTEM is now macEM: the app, its DMG, its window and menus, its exports and the store texts carry the new name ([#505](https://github.com/mac4DSTEM/macTEM/issues/505)) ([fd1206a](https://github.com/mac4DSTEM/macTEM/commit/fd1206ab3c007ce73f6a2fce5815f279ece86f32))
* Maps room histograms, several selected grains and their poles on the pole figures ([#246](https://github.com/mac4DSTEM/macTEM/issues/246)) ([8729c67](https://github.com/mac4DSTEM/macTEM/commit/8729c67c26af527596825f52cfc8bfac8c5e1e2d))
* Maps room with IPF and phase maps, colour keys and hover readout of .ang and .ctf maps (F6 on screen) ([#199](https://github.com/mac4DSTEM/macTEM/issues/199)) ([cb0e226](https://github.com/mac4DSTEM/macTEM/commit/cb0e2267b15ff739c108960ca14d0c59805c0cab))
* open Bruker .bcf/.spx, EDAX .spd/.lsd/.spc and JEOL .pts/.eds/.img/.asw SEM-EDS files ([#164](https://github.com/mac4DSTEM/macTEM/issues/164)) ([5b050d4](https://github.com/mac4DSTEM/macTEM/commit/5b050d4e8203e1c4ef6c81ad0ab3781f25f219a0))
* Open in Maps shows the Indexing room's run in the Maps room, with a Source pop-up and a stale mark ([#244](https://github.com/mac4DSTEM/macTEM/issues/244)) ([dffe6cd](https://github.com/mac4DSTEM/macTEM/commit/dffe6cd76b01fd67055aa8c0a2e19b3b82118dec))
* open NORDIF Pattern.dat in the Patterns room ([#175](https://github.com/mac4DSTEM/macTEM/issues/175)) ([5bb3dac](https://github.com/mac4DSTEM/macTEM/commit/5bb3dac253ce9556274120e271bf0f1edf57d9a0))
* open Oxford .ebsp/.ctf and EDAX .up1/.up2/.ang scans in the Patterns room as one EBSDDataset ([#161](https://github.com/mac4DSTEM/macTEM/issues/161)) ([6fd2189](https://github.com/mac4DSTEM/macTEM/commit/6fd218926b8806f39a0601f26606d300ecf7edc4))
* orientation core (rotations, 32 point groups, fundamental zones, orientations and misorientations) against orix 0.15.0 ([#162](https://github.com/mac4DSTEM/macTEM/issues/162)) ([2a46109](https://github.com/mac4DSTEM/macTEM/commit/2a461092fb74f30d2f6cf4a082620b6ff245cba4))
* orientation similarity map and merge of dictionary-indexed maps as kikuchipy does ([#221](https://github.com/mac4DSTEM/macTEM/issues/221)) ([985e3d4](https://github.com/mac4DSTEM/macTEM/commit/985e3d42168399f1fa4bbba98c3f9232b69fdc47))
* Patterns and Indexing have one Display section with a Map · Pattern switch ([#402](https://github.com/mac4DSTEM/macTEM/issues/402)) ([fe87c40](https://github.com/mac4DSTEM/macTEM/commit/fe87c40c9293b3204975b887daa06076cafb8a4c))
* Patterns room ⌘6 browses EBSD pattern datasets (scan map, live pattern pane, calibration) ([#144](https://github.com/mac4DSTEM/macTEM/issues/144)) ([0860add](https://github.com/mac4DSTEM/macTEM/commit/0860addee1e419f986907e8e254fa961458b0438))
* pole figures, inverse pole figure densities and ODF sections against orix (figure F13) ([#196](https://github.com/mac4DSTEM/macTEM/issues/196)) ([24bb4b3](https://github.com/mac4DSTEM/macTEM/commit/24bb4b3013a9635c2933f7200979827354e556b4))
* process EBSD patterns in the Patterns room (static and dynamic background, rescale or normalise, binning) as kikuchipy does ([#190](https://github.com/mac4DSTEM/macTEM/issues/190)) ([13e7ccc](https://github.com/mac4DSTEM/macTEM/commit/13e7ccc939f24865495917b866ece4e03011087f))
* read EDAX .up1/.up2 pattern files and .ang orientation maps in TEMCore ([#138](https://github.com/mac4DSTEM/macTEM/issues/138)) ([d515bc4](https://github.com/mac4DSTEM/macTEM/commit/d515bc478204d03ea4f317f34dcce51103df0efd))
* read EMsoft master patterns and project them onto the EBSD detector as kikuchipy does (figure F15) ([#160](https://github.com/mac4DSTEM/macTEM/issues/160)) ([d18a5e7](https://github.com/mac4DSTEM/macTEM/commit/d18a5e7abaffab109fe5654a5735c1b3d9069234))
* read h5ebsd EBSD pattern files (kikuchipy, Bruker, EDAX, Oxford H5OINA) in TEMCore ([#125](https://github.com/mac4DSTEM/macTEM/issues/125)) ([d7117b9](https://github.com/mac4DSTEM/macTEM/commit/d7117b9ccb0cdc5e13b380676fd21291e90a80cc))
* read NORDIF EBSD acquisitions (Pattern.dat, Setting.txt, calibration patterns) as kikuchipy does ([#129](https://github.com/mac4DSTEM/macTEM/issues/129)) ([7d0f896](https://github.com/mac4DSTEM/macTEM/commit/7d0f89679c19a5829973364e309ad46b3c2761e4))
* read Oxford .ebsp patterns and .ctf orientation maps against kikuchipy and orix ([#135](https://github.com/mac4DSTEM/macTEM/issues/135)) ([adeebf2](https://github.com/mac4DSTEM/macTEM/commit/adeebf265c993713cb1d049636a45c07fff4992f))
* refine EBSD orientations and projection centres against the master pattern as kikuchipy does (figure F10) ([#214](https://github.com/mac4DSTEM/macTEM/issues/214)) ([3c5930e](https://github.com/mac4DSTEM/macTEM/commit/3c5930e93324368171c66142cb881d2a94bc1c0a))
* sample orientations on the cubochoric grid in a fundamental zone or around an orientation, against orix 0.15.0 ([#168](https://github.com/mac4DSTEM/macTEM/issues/168)) ([18302ef](https://github.com/mac4DSTEM/macTEM/commit/18302ef2aad39f58e36ba07285bf5dd4c0a357e0))
* Schmid factors, slip traces and GND density of EBSD maps against DefDAP 1.3.1 ([#170](https://github.com/mac4DSTEM/macTEM/issues/170)) ([e67cb6d](https://github.com/mac4DSTEM/macTEM/commit/e67cb6d4df4e12cb4cd485d99c313eb079b90505))
* SEM parity harness, north-star data and reference bundles for milestone 1 ([#130](https://github.com/mac4DSTEM/macTEM/issues/130)) ([d2afafe](https://github.com/mac4DSTEM/macTEM/commit/d2afafed6f7d9e7fddf6db2a4f48f0ab50b7ab5b))
* SEM session report and the SEM rows in the Results room (P8-02) ([#241](https://github.com/mac4DSTEM/macTEM/issues/241)) ([6262cea](https://github.com/mac4DSTEM/macTEM/commit/6262cea182cf86a339009a755ff0858421464d21))
* SEM TIFF metadata (Thermo, Zeiss, Tescan) in the Image room, databar cropped ([#136](https://github.com/mac4DSTEM/macTEM/issues/136)) ([a3436f0](https://github.com/mac4DSTEM/macTEM/commit/a3436f0aacfe0681bcf203edcde39324a651586f))
* SEM-EDS line intensities with background windows and Cliff-Lorimer quantification against exspy (figures F16, F17) ([#155](https://github.com/mac4DSTEM/macTEM/issues/155)) ([73e2124](https://github.com/mac4DSTEM/macTEM/commit/73e21240c606a17e2b79f528bdc87990b4bcfe62))
* ship the SEM demo data (Ni EBSD patterns, BAM TM002 spectrum) and open the spectrum from Try Demo Data ([#127](https://github.com/mac4DSTEM/macTEM/issues/127)) ([f95b7d9](https://github.com/mac4DSTEM/macTEM/commit/f95b7d99e74f28c97e3ff89f7a1f23a2a1927753))
* show the SEM databar as a strip under the picture ([#229](https://github.com/mac4DSTEM/macTEM/issues/229)) ([4e40618](https://github.com/mac4DSTEM/macTEM/commit/4e406184cc7012c96aa21147c6030df60eb2d1b1))
* static and dynamic background removal of EBSD patterns in TEMCore (figure F2) ([#133](https://github.com/mac4DSTEM/macTEM/issues/133)) ([eeb7660](https://github.com/mac4DSTEM/macTEM/commit/eeb7660a4a3bf0af783990a853f8d2c833568fef))
* the EDS room's region tools and Pin Region in the Workspace menu on ⌃⌘0…4 ([#446](https://github.com/mac4DSTEM/macTEM/issues/446)) ([63ea5bf](https://github.com/mac4DSTEM/macTEM/commit/63ea5bfa75c05b3210df638b32dad2b0ab7f281b))
* the EELS results table selects its edges and ⌘C copies them as tab-separated text ([#353](https://github.com/mac4DSTEM/macTEM/issues/353)) ([8a97f0f](https://github.com/mac4DSTEM/macTEM/commit/8a97f0f6d96abc00383692a18b1ee93a40bee7b9))
* the SEM maps open on their 1st to 99th percentile, so a few outliers no longer wash a map out ([#416](https://github.com/mac4DSTEM/macTEM/issues/416)) ([224945b](https://github.com/mac4DSTEM/macTEM/commit/224945b38fd44af2f779e5938c0057c826a69ece))
* the sidebar is the workspaces alone; the window's tabs are the open files ([#449](https://github.com/mac4DSTEM/macTEM/issues/449)) ([d0bfb53](https://github.com/mac4DSTEM/macTEM/commit/d0bfb538650c6fe2df32006972bc0185993214ce))
* the sidebar lists five workspaces with their parts underneath, as mac4DSTEM's does ([#399](https://github.com/mac4DSTEM/macTEM/issues/399)) ([7ab4579](https://github.com/mac4DSTEM/macTEM/commit/7ab4579dd62bdcc0565b1da25202833edde22a11))
* the workspaces read Imaging, Diffraction, EBSD, Spectroscopy, Results (⌘1…⌘5 follow) ([#474](https://github.com/mac4DSTEM/macTEM/issues/474)) ([d2243da](https://github.com/mac4DSTEM/macTEM/commit/d2243da2fb9220fcd58b7466e7ab30c121f6ab72))
* vectors, Miller indices, stereographic projection and IPF colour keys against orix 0.15.0 (figure F6) ([#172](https://github.com/mac4DSTEM/macTEM/issues/172)) ([71a6f40](https://github.com/mac4DSTEM/macTEM/commit/71a6f40b4d96b5f33861ea51ab65556c7e4ca7cf))
* virtual BSE images in the Patterns room (detector grid, tiles, colour mix) reproduce north-star figure F1 ([#174](https://github.com/mac4DSTEM/macTEM/issues/174)) ([d6d497b](https://github.com/mac4DSTEM/macTEM/commit/d6d497b1f1800c81fb6e9413d24809bace88e463))
* write EBSD crystal maps as .ang and .ctf that orix reads back (figure F18) ([#185](https://github.com/mac4DSTEM/macTEM/issues/185)) ([33ea462](https://github.com/mac4DSTEM/macTEM/commit/33ea462ff9886444d39782f052c0d57acb1877fa))


### Bug Fixes

* a file macTEM may not read says so instead of blaming its format, and a refused file leaves no empty tab ([#486](https://github.com/mac4DSTEM/macTEM/issues/486)) ([a29c9e1](https://github.com/mac4DSTEM/macTEM/commit/a29c9e1f0d1a90547fb2cd5d97626136c03af503))
* a pattern file read through its handle lets each row go as the pass moves on ([#471](https://github.com/mac4DSTEM/macTEM/issues/471)) ([5fbf725](https://github.com/mac4DSTEM/macTEM/commit/5fbf7258e729e47f25557896a134a10e15e87bab))
* a quit question asked from the background bounces the Dock icon, and File &gt; Close Map closes only the map shown ([#503](https://github.com/mac4DSTEM/macTEM/issues/503)) ([6b530ff](https://github.com/mac4DSTEM/macTEM/commit/6b530ff4c873fe3bc94f73cbe5e88fcb197c5c8e))
* an ended Indexing run lets go of the processed scan it read ([#504](https://github.com/mac4DSTEM/macTEM/issues/504)) ([1a09757](https://github.com/mac4DSTEM/macTEM/commit/1a09757191964f5ed6d5d7ec76d3ccc0dab45c81))
* an infinite NORDIF scaling factor scales every value to 0 again, as kikuchipy ([#450](https://github.com/mac4DSTEM/macTEM/issues/450)) ([471c3be](https://github.com/mac4DSTEM/macTEM/commit/471c3be064d1f8592538202903962515d0ffb4b3))
* an SEM TIFF's Info shows each acquisition field once, without the TEM-only "Not recorded" rows ([#418](https://github.com/mac4DSTEM/macTEM/issues/418)) ([a28a9b0](https://github.com/mac4DSTEM/macTEM/commit/a28a9b03034316a4ab77a2318aad016ea2533abc))
* closing an image or quitting asks before discarding unsaved marks or a running analysis ([#372](https://github.com/mac4DSTEM/macTEM/issues/372)) ([4927b8c](https://github.com/mac4DSTEM/macTEM/commit/4927b8c879ac2f94a69063364f4e16001bf03eb2))
* damaged SEM files are refused in words instead of quitting the app, Open Recent lists only files that opened, and a test that starts to skip fails CI ([#441](https://github.com/mac4DSTEM/macTEM/issues/441)) ([8e2f0ee](https://github.com/mac4DSTEM/macTEM/commit/8e2f0eec35de909dfb4775d1e7c9b087bb4b068b))
* **ebsd:** a NORDIF Pattern.dat whose Setting.txt cannot be read says so ([#360](https://github.com/mac4DSTEM/macTEM/issues/360)) ([66a0f3b](https://github.com/mac4DSTEM/macTEM/commit/66a0f3b8fc0b44c7e94575847ffd61a2bedc9547))
* **ebsd:** bad h5ebsd header numbers are refused, and pattern files on network volumes no longer crash when the volume goes away ([#366](https://github.com/mac4DSTEM/macTEM/issues/366)) ([91cfd0c](https://github.com/mac4DSTEM/macTEM/commit/91cfd0c21229209fa32b46131b756686d1f52e8a))
* **ebsd:** damaged .ang, .ctf and crystal-map coordinates are refused instead of crashing the Maps room ([#364](https://github.com/mac4DSTEM/macTEM/issues/364)) ([6b05064](https://github.com/mac4DSTEM/macTEM/commit/6b050640517e47892564c264b21a641f357c2429))
* **ebsd:** damaged .up1/.up2, NORDIF and .ebsp headers are refused instead of crashing the app ([#362](https://github.com/mac4DSTEM/macTEM/issues/362)) ([a561750](https://github.com/mac4DSTEM/macTEM/commit/a5617506a7e31c4ebdfea98ce3804c10e97a2746))
* **eds:** damaged Bruker, JEOL, EDAX and EMsoft files are refused instead of crashing or filling memory ([#370](https://github.com/mac4DSTEM/macTEM/issues/370)) ([341f7a0](https://github.com/mac4DSTEM/macTEM/commit/341f7a04a106d42e35d4f669e39da3a35192efe1))
* exported CSVs quote names, JEOL maps can be cancelled, the Patterns cache is bounded, and CI compiles the UI journeys ([#438](https://github.com/mac4DSTEM/macTEM/issues/438)) ([20a8fec](https://github.com/mac4DSTEM/macTEM/commit/20a8fecda20e2e1eef61ae1e29e9d15ee20b5ebd))
* exports write numbers the same in every locale, screen numbers round like the files, and long runs keep the Mac awake ([#419](https://github.com/mac4DSTEM/macTEM/issues/419)) ([63bc587](https://github.com/mac4DSTEM/macTEM/commit/63bc587c5c24108d85222a14c2d3af10a8881e4d))
* Help &gt; Open Demo Data works with no window open ([#443](https://github.com/mac4DSTEM/macTEM/issues/443)) ([a25ad20](https://github.com/mac4DSTEM/macTEM/commit/a25ad2096e2ececc1d9e8709f656b12d701a8b4d))
* huge or non-finite numbers in a SEM TIFF header or a typed processing field no longer crash the app ([#368](https://github.com/mac4DSTEM/macTEM/issues/368)) ([83f274d](https://github.com/mac4DSTEM/macTEM/commit/83f274dd935e55960e14591bea2159ca3d98574d))
* Maps reads an h5ebsd crystal map's length unit, so the Ni scale bar and grain sizes are in µm ([#390](https://github.com/mac4DSTEM/macTEM/issues/390)) ([ab0f15d](https://github.com/mac4DSTEM/macTEM/commit/ab0f15d3cedbc6a01e5e8c7c12ecf99a5f0536ef))
* NORDIF settings lines end and [Area] values read as kikuchipy reads them ([#456](https://github.com/mac4DSTEM/macTEM/issues/456)) ([028ae5a](https://github.com/mac4DSTEM/macTEM/commit/028ae5adf943ac05100f4237c0903d7a43b04291)), closes [#448](https://github.com/mac4DSTEM/macTEM/issues/448) [#452](https://github.com/mac4DSTEM/macTEM/issues/452)
* on a render, macTEM's scale bar starts hidden so it does not cover the render's own ([#483](https://github.com/mac4DSTEM/macTEM/issues/483)) ([ff5046a](https://github.com/mac4DSTEM/macTEM/commit/ff5046a6b6e027b8ee5b1cc4b6e1d7075c7ae976))
* Open Recent, drops, stack frames and Cancel answer what happened, Stop ends Segment and KAM, and Process uses every core ([#417](https://github.com/mac4DSTEM/macTEM/issues/417)) ([7dbb25e](https://github.com/mac4DSTEM/macTEM/commit/7dbb25e372be8b1cab65355272858cd47b5d2ac6))
* **parity:** pin numpy to its AVX2 kernels in the SEM emit so the texture bundles reproduce on every runner ([a8ddd37](https://github.com/mac4DSTEM/macTEM/commit/a8ddd3725e932edca33cfe2e11ffcb6efc5efcb6))
* **parity:** pin numpy's AVX2 kernels in the SEM emit so the texture bundles reproduce on every runner ([#223](https://github.com/mac4DSTEM/macTEM/issues/223)) ([a8ddd37](https://github.com/mac4DSTEM/macTEM/commit/a8ddd3725e932edca33cfe2e11ffcb6efc5efcb6))
* Particles, EELS and EDS no longer stay stale after a preview, a Stop or a same-named file ([#374](https://github.com/mac4DSTEM/macTEM/issues/374)) ([ac6f75a](https://github.com/mac4DSTEM/macTEM/commit/ac6f75a757556d027c8a0c395a244f65bca5f6fb))
* **patterns:** a new Grid or a Stop during a pass no longer blocks Process or drops the new run ([#389](https://github.com/mac4DSTEM/macTEM/issues/389)) ([a953970](https://github.com/mac4DSTEM/macTEM/commit/a9539701f425faccff16c0ad31ff25a740ab8597))
* **patterns:** NLPAR and averaging no longer copy the whole scan, and Process refuses a scan that would not fit in memory ([#400](https://github.com/mac4DSTEM/macTEM/issues/400)) ([ac028f0](https://github.com/mac4DSTEM/macTEM/commit/ac028f03cc8ba0c58c710ac1de4f95fe1c01a693))
* read real Tescan TIFF headers as NexusLIMS does ([#220](https://github.com/mac4DSTEM/macTEM/issues/220)) ([b4fea49](https://github.com/mac4DSTEM/macTEM/commit/b4fea49e87f501b8833bbb93a2980d7225933f9f))
* stopping the texture leaves the Pole figures and ODF panes saying what happened, with a way to compute it ([#499](https://github.com/mac4DSTEM/macTEM/issues/499)) ([09b4085](https://github.com/mac4DSTEM/macTEM/commit/09b40851900e95fb23e546cde827f5dd4ee12827))
* TEMCore builds with Xcode 27.1 again ([#444](https://github.com/mac4DSTEM/macTEM/issues/444)) ([a611894](https://github.com/mac4DSTEM/macTEM/commit/a611894bcad866be761fe9de32b1fc5d29ab892c))
* the diffraction readout keeps a crystal name holding a line break on its header line ([#462](https://github.com/mac4DSTEM/macTEM/issues/462)) ([44d2fd1](https://github.com/mac4DSTEM/macTEM/commit/44d2fd152be3734fb1bb67fff0273274eca507ab))
* the EDS room shows the SEM line table and window quantification for an SEM spectrum ([#249](https://github.com/mac4DSTEM/macTEM/issues/249)) ([f24204b](https://github.com/mac4DSTEM/macTEM/commit/f24204bc54c61be1e9d55d45fb3d1330b1590b10))
* the EELS Regions table writes a region's total counts without grouping ([#485](https://github.com/mac4DSTEM/macTEM/issues/485)) ([96e7ec5](https://github.com/mac4DSTEM/macTEM/commit/96e7ec5014464ac37f3772e8300225dc1ad26664)), closes [#481](https://github.com/mac4DSTEM/macTEM/issues/481)
* the EELS results pane shows every fitted edge before the regions, and Exact NNLS's Fit to reads in full ([#455](https://github.com/mac4DSTEM/macTEM/issues/455)) ([8a97f0f](https://github.com/mac4DSTEM/macTEM/commit/8a97f0f6d96abc00383692a18b1ee93a40bee7b9))
* the EELS spectrum follows a drawn, picked or cleared region at once and names it, not the drag's last live shape ([#494](https://github.com/mac4DSTEM/macTEM/issues/494)) ([8a97f0f](https://github.com/mac4DSTEM/macTEM/commit/8a97f0f6d96abc00383692a18b1ee93a40bee7b9))
* the File menu lists every room's exports, EELS windows can be set without dragging, and zoom and copy work in the FFT and Diffraction rooms ([#439](https://github.com/mac4DSTEM/macTEM/issues/439)) ([6f6d1ec](https://github.com/mac4DSTEM/macTEM/commit/6f6d1ec2bb3f68aaabb747582c06df46f1d42aae))
* the Indexing room writes its numbers one way and says Detector tilt ([#476](https://github.com/mac4DSTEM/macTEM/issues/476)) ([a67cd2b](https://github.com/mac4DSTEM/macTEM/commit/a67cd2b8b9607b13f6e3adf6cb158d57239de584))
* the Indexing room's detected bands draw on a solid dark track, as in mac4DSTEM ([#482](https://github.com/mac4DSTEM/macTEM/issues/482)) ([c21525f](https://github.com/mac4DSTEM/macTEM/commit/c21525f7252209ee8d0ff194ca30a7b1cfa4280b))
* the Indexing room's disorientation histogram draws only occupied bins, not a row of dots along zero ([#394](https://github.com/mac4DSTEM/macTEM/issues/394)) ([11e7389](https://github.com/mac4DSTEM/macTEM/commit/11e7389d3ae53d74479acb68985821f8d64dd1e6))
* the Maps and Patterns rooms write their numbers one way, grain lengths read alike, and the quality maps come before the tiles ([#451](https://github.com/mac4DSTEM/macTEM/issues/451)) ([01714c8](https://github.com/mac4DSTEM/macTEM/commit/01714c80f1accd829253591be3bb9af390d9762c))
* the Maps room's bottom tabs stay at the top of their pane, and the colour key and ODF sections read in full ([#393](https://github.com/mac4DSTEM/macTEM/issues/393)) ([e8ff992](https://github.com/mac4DSTEM/macTEM/commit/e8ff9928b371bc26ad5822dc1a054c0aaced788f))
* the planted comparison's inputs are normalised without BLAS, the same bits on every CPU ([#447](https://github.com/mac4DSTEM/macTEM/issues/447)) ([4eddab5](https://github.com/mac4DSTEM/macTEM/commit/4eddab586c2e184a0a9043e6a38da4edebd156eb))
* the SEM maps pick on click or drag, and hover only reads, as in mac4DSTEM ([#490](https://github.com/mac4DSTEM/macTEM/issues/490)) ([e9b66fc](https://github.com/mac4DSTEM/macTEM/commit/e9b66fcd03043ed28459b8d35dca162dbed8e06f))
* the SEM reference check no longer goes red when the Hough map comes back as another cubic twin ([#454](https://github.com/mac4DSTEM/macTEM/issues/454)) ([62a1cac](https://github.com/mac4DSTEM/macTEM/commit/62a1cace3eda31fc31d23ed1105389edf68719c2))
* the SEM rooms speak their bars, readout and headers, and the Grains table copies with ⌘C ([#477](https://github.com/mac4DSTEM/macTEM/issues/477)) ([67776be](https://github.com/mac4DSTEM/macTEM/commit/67776be8f36970d8e5ba5178c52964af82ce38e0))
* the SEM rooms speak their opening bars, pattern readout and column headers, and the Grains table copies with ⌘C ([67776be](https://github.com/mac4DSTEM/macTEM/commit/67776be8f36970d8e5ba5178c52964af82ce38e0))
* the SEM rooms write their remaining numbers through Num and UnitDisplay, never grouped ([#501](https://github.com/mac4DSTEM/macTEM/issues/501)) ([87489ea](https://github.com/mac4DSTEM/macTEM/commit/87489ea20b66f241280e521afbb8351150941934))
* the SEM rooms' status lines write their numbers in the reader's locale ([#484](https://github.com/mac4DSTEM/macTEM/issues/484)) ([ede69df](https://github.com/mac4DSTEM/macTEM/commit/ede69df554f840ff3872a1fb643f9dd954c6c684))
* the SEM tables take the keyboard when clicked, so ⌘C copies their rows, and their headers are spoken in words ([#502](https://github.com/mac4DSTEM/macTEM/issues/502)) ([2145ec5](https://github.com/mac4DSTEM/macTEM/commit/2145ec5d089d7ec093d3e69b54ab08bbdfbc24ac))
* the SEM-EDS rows drop the window composition and write their numbers in the locale they are given ([#414](https://github.com/mac4DSTEM/macTEM/issues/414)) ([d2e2065](https://github.com/mac4DSTEM/macTEM/commit/d2e2065425239a6f7997cc6ba076dc6c7bf7d0e4))
* the session record's refusals write their byte and entry counts ungrouped ([#300](https://github.com/mac4DSTEM/macTEM/issues/300)) ([8a97f0f](https://github.com/mac4DSTEM/macTEM/commit/8a97f0f6d96abc00383692a18b1ee93a40bee7b9))
* the session report and the dictionary method JSON write the Refine and energy words with a decimal point ([#458](https://github.com/mac4DSTEM/macTEM/issues/458)) ([f47813f](https://github.com/mac4DSTEM/macTEM/commit/f47813fa1adf363028f6f0e727909652a49b48d1))
* vendor EBSD pairs and EDAX EDS maps open with their companion files in the sandboxed app ([#395](https://github.com/mac4DSTEM/macTEM/issues/395)) ([418f2db](https://github.com/mac4DSTEM/macTEM/commit/418f2db7d2ef5aedd1e1b7d80b9cd349900869c0))
* VoiceOver names the image-opening spinner and the FFT spectrum pane's spinners ([#467](https://github.com/mac4DSTEM/macTEM/issues/467)) ([5a9ab7b](https://github.com/mac4DSTEM/macTEM/commit/5a9ab7b7cc0dcfebac0c3f92d56639218e64898b))
* VoiceOver reads the pixel under the pointer in the Image and Diffraction panes ([#457](https://github.com/mac4DSTEM/macTEM/issues/457)) ([515f6c6](https://github.com/mac4DSTEM/macTEM/commit/515f6c65552e2532a28602f31bec0f765a804b52))
* whole numbers on screen carry no grouping separator in the EELS room and the Image, FFT and Particles controls ([#488](https://github.com/mac4DSTEM/macTEM/issues/488)) ([8a97f0f](https://github.com/mac4DSTEM/macTEM/commit/8a97f0f6d96abc00383692a18b1ee93a40bee7b9))

## [1.3.0](https://github.com/mac4DSTEM/macTEM/compare/v1.2.0...v1.3.0) (2026-11-05)


### Features

* EELS Align signal range and crop are real controls ([#87](https://github.com/mac4DSTEM/macTEM/issues/87)) ([7a681d0](https://github.com/mac4DSTEM/macTEM/commit/7a681d0819743a2fb0e3d21c6ccb25fa310f76b4))
* Help &gt; Open Demo Data opens the generated demo documents ([#108](https://github.com/mac4DSTEM/macTEM/issues/108)) ([f9d7dfb](https://github.com/mac4DSTEM/macTEM/commit/f9d7dfb991487e5a9c78e52a21f0aa02cb310f46))


### Bug Fixes

* EELS fit notes popover and fit-quality line read cleanly ([#96](https://github.com/mac4DSTEM/macTEM/issues/96)) ([8855eee](https://github.com/mac4DSTEM/macTEM/commit/8855eee05b531c97516a00f41542c4bdc8ab633a))
* EELS spectrum legend no longer covers the low loss and core loss labels ([#93](https://github.com/mac4DSTEM/macTEM/issues/93)) ([4b68682](https://github.com/mac4DSTEM/macTEM/commit/4b6868258bbf0ad9159ca5b85a1fff15de6b3a24))
* Particles Export CSV writes into --export-dir and reports its result ([#98](https://github.com/mac4DSTEM/macTEM/issues/98)) ([d3c5cb8](https://github.com/mac4DSTEM/macTEM/commit/d3c5cb8350db3b0fa1bed2587fb0fb07c3190d7e))
* remember files the sandbox grants read-only ([#114](https://github.com/mac4DSTEM/macTEM/issues/114)) ([ec59da7](https://github.com/mac4DSTEM/macTEM/commit/ec59da7b1770bf0d09db9d92dc775998ebacf808))

## [1.2.0](https://github.com/mac4DSTEM/macTEM/compare/v1.1.1...v1.2.0) (2026-11-02)


### Features

* EELS keyboard regions, hovered pixel spectrum and profile labels ([#82](https://github.com/mac4DSTEM/macTEM/issues/82)) ([36aadd5](https://github.com/mac4DSTEM/macTEM/commit/36aadd518e6a7559ba4e00e5f9293d05ba1f629d))
* EELS Maps status line while maps are computed ([#78](https://github.com/mac4DSTEM/macTEM/issues/78)) ([3b3812d](https://github.com/mac4DSTEM/macTEM/commit/3b3812da73e01b22767b65f6503c9372bfeff7ae))
* EELS MLLS fit uses the reference spectra ([#90](https://github.com/mac4DSTEM/macTEM/issues/90)) ([903f3b9](https://github.com/mac4DSTEM/macTEM/commit/903f3b9608bedaf156adb7da65bf6924b4eb78ab))
* EELS results footer opens the fit notes, as the EDS room ([#81](https://github.com/mac4DSTEM/macTEM/issues/81)) ([124d663](https://github.com/mac4DSTEM/macTEM/commit/124d6632e3abe7d8ed520a2c2f9f64791e137810))
* EELS room keyboard regions, the hovered pixel's spectrum and profile labels ([36aadd5](https://github.com/mac4DSTEM/macTEM/commit/36aadd518e6a7559ba4e00e5f9293d05ba1f629d))
* EELS single spectrum and stage state on the section titles ([#77](https://github.com/mac4DSTEM/macTEM/issues/77)) ([521675d](https://github.com/mac4DSTEM/macTEM/commit/521675d1c7c32721f5df3bc998d80669d3b47139))
* EELS Spectrum MSA export, method JSON SHA-256, Info tilts and beam source ([#79](https://github.com/mac4DSTEM/macTEM/issues/79)) ([e2bd1f6](https://github.com/mac4DSTEM/macTEM/commit/e2bd1f6b7db8adacabd5b369c2981b69206229b1))


### Bug Fixes

* EELS profile lists only the shown maps; the hovered spectrum shows in light mode ([#84](https://github.com/mac4DSTEM/macTEM/issues/84)) ([d49acb1](https://github.com/mac4DSTEM/macTEM/commit/d49acb13514b2d23d2f1c61807dbdf9dcdc3923a))
* EELS results table shows at% and wt% without clipping ([#88](https://github.com/mac4DSTEM/macTEM/issues/88)) ([7383d0f](https://github.com/mac4DSTEM/macTEM/commit/7383d0f07414496d848cd790e9238d486d8f69c4))
* EELS ZLP shift tile contrast and the empty tooltip on the colour mix ([#91](https://github.com/mac4DSTEM/macTEM/issues/91)) ([1d43ad8](https://github.com/mac4DSTEM/macTEM/commit/1d43ad8cd2f329ae134456feae78a4569f4e3e30))
* Open Files shows the scan size of an EELS spectrum image ([#89](https://github.com/mac4DSTEM/macTEM/issues/89)) ([a701ded](https://github.com/mac4DSTEM/macTEM/commit/a701ded5083d0fb39410a1030c6dd6124488a980))
* the EELS room opens a single spectrum ([#85](https://github.com/mac4DSTEM/macTEM/issues/85)) ([77d81fc](https://github.com/mac4DSTEM/macTEM/commit/77d81fca95de9f0522cb655fac69b603e4d1bda5))

## [1.1.1](https://github.com/mac4DSTEM/macTEM/compare/v1.1.0...v1.1.1) (2026-11-02)


### Bug Fixes

* the app version comes from the release tag ([#75](https://github.com/mac4DSTEM/macTEM/issues/75)) ([5994de9](https://github.com/mac4DSTEM/macTEM/commit/5994de9bbe6fb5f0a5399ecd9c352db2667423c6))

## [1.1.0](https://github.com/mac4DSTEM/macTEM/compare/v1.0.0...v1.1.0) (2026-11-01)


### Features

* EELS results carry sigma on at% and wt%, the fit quality and an MLLS Fit to ([#61](https://github.com/mac4DSTEM/macTEM/issues/61)) ([e6ff757](https://github.com/mac4DSTEM/macTEM/commit/e6ff757a908c9e297474adba6672d0698e69b688))
* EELS room deconvolution stage, MLLS fit model and Fit only role ([#58](https://github.com/mac4DSTEM/macTEM/issues/58)) ([cd78122](https://github.com/mac4DSTEM/macTEM/commit/cd7812245e4e8bfab5d527c914da0493fc102778))
* EELS wt% maps and a display filter ([#67](https://github.com/mac4DSTEM/macTEM/issues/67)) ([0e736f3](https://github.com/mac4DSTEM/macTEM/commit/0e736f3723808b9f1b40b247c9d4e26b19fc1c10))
* Find Spots ranks by local contrast and shows it in the spot row ([#38](https://github.com/mac4DSTEM/macTEM/issues/38)) ([b1b1b3b](https://github.com/mac4DSTEM/macTEM/commit/b1b1b3b74b8b663e11134ba6621890160bafc274))
* particles take Otsu's threshold, remove objects below the minimum area and report the areal density ([#37](https://github.com/mac4DSTEM/macTEM/issues/37)) ([59f211f](https://github.com/mac4DSTEM/macTEM/commit/59f211f41c329d2eaa5329ad8c0e2d02fd3b9df5))
* results no longer carry an unvalidated badge ([#63](https://github.com/mac4DSTEM/macTEM/issues/63)) ([12c2b34](https://github.com/mac4DSTEM/macTEM/commit/12c2b34dad28676b9ff9a2005c4623bfd130dc61))
* the busy line shows elapsed time, and an ETA where the work reports progress ([#45](https://github.com/mac4DSTEM/macTEM/issues/45)) ([02bfc77](https://github.com/mac4DSTEM/macTEM/commit/02bfc77f567c1d7ab7d4276dbae3c65276e64790))
* the EDX room comes from MacEMUI ([#22](https://github.com/mac4DSTEM/macTEM/issues/22)) ([e1165e7](https://github.com/mac4DSTEM/macTEM/commit/e1165e7117544c8d570a8cda59ea6faa38e2c997))
* the EELS room no longer labels results as unvalidated ([#65](https://github.com/mac4DSTEM/macTEM/issues/65)) ([3fc255c](https://github.com/mac4DSTEM/macTEM/commit/3fc255c2041954c8f948f2c22a46aa3bc0e14093))
* the Particles object table is a window, the pointer names the object under it, and the section sits above Measure ([#42](https://github.com/mac4DSTEM/macTEM/issues/42)) ([242ff56](https://github.com/mac4DSTEM/macTEM/commit/242ff56b15f0a0851be077504b909ce4e96b6fe8))
* the Results room lists the EDS composition of the file ([#41](https://github.com/mac4DSTEM/macTEM/issues/41)) ([849c3ba](https://github.com/mac4DSTEM/macTEM/commit/849c3baa8fe00ee909e37eb72ebe9643e9f4e147))
* the Results room lists the EELS thickness and fitted edges of the file ([#50](https://github.com/mac4DSTEM/macTEM/issues/50)) ([113ccf5](https://github.com/mac4DSTEM/macTEM/commit/113ccf56c58179cac8bcaea5296f2cb8a91eff4d))


### Bug Fixes

* a lone spectrum file highlights only its own room in the sidebar ([#47](https://github.com/mac4DSTEM/macTEM/issues/47)) ([369d626](https://github.com/mac4DSTEM/macTEM/commit/369d6263228e592cd36f8d8cca56786b261b114f))
* a re-read with other pixels drops the particle report; ImagoKit 0.8.0 ([#26](https://github.com/mac4DSTEM/macTEM/issues/26)) ([add48f4](https://github.com/mac4DSTEM/macTEM/commit/add48f426b54c55390bf7d59793e1e198a04c7e6))
* a session re-save keeps another writer's lineage keys and refuses a rewritten or deleted sidecar ([#33](https://github.com/mac4DSTEM/macTEM/issues/33)) ([795ac30](https://github.com/mac4DSTEM/macTEM/commit/795ac30554aa01a56a50b8eb6e82e9c2402cbfe3))
* a single .msa spectrum opens from Finder, the Open panel and a drop ([#34](https://github.com/mac4DSTEM/macTEM/issues/34)) ([d7605fc](https://github.com/mac4DSTEM/macTEM/commit/d7605fcd8abae4fe6ed4c5c8b803bc01d12fa2bd))
* exports carry no milestone ids in their validation and lineage text ([#16](https://github.com/mac4DSTEM/macTEM/issues/16)) ([44edfdb](https://github.com/mac4DSTEM/macTEM/commit/44edfdb358f9a891fe99b0e7bae6e1ad57564029))
* macTEM texts drop the unvalidated wording ([cc778be](https://github.com/mac4DSTEM/macTEM/commit/cc778be64931eada4e5c4c37a5d31f51ad89d1fb))
* Particles numbers use the locale decimal mark ([#48](https://github.com/mac4DSTEM/macTEM/issues/48)) ([2f7d726](https://github.com/mac4DSTEM/macTEM/commit/2f7d726dfaa30a587e9ff4a89ff4e48c2de0a653))
* refuse a save after a re-read with other pixels, offer Save Anyway ([#27](https://github.com/mac4DSTEM/macTEM/issues/27)) ([2f07578](https://github.com/mac4DSTEM/macTEM/commit/2f0757843986332d55b1a378be6cfaab96b2075e))
* the busy line names the running operation, not the last status sentence ([#49](https://github.com/mac4DSTEM/macTEM/issues/49)) ([49c63aa](https://github.com/mac4DSTEM/macTEM/commit/49c63aa266956b318e78d04eddcb70b216f31d31))
* the Save to Session title follows a grant stored or dropped while the file is open ([#35](https://github.com/mac4DSTEM/macTEM/issues/35)) ([fd19a40](https://github.com/mac4DSTEM/macTEM/commit/fd19a4008aba3364f0d6c5fe407cebcbb3108fe2))
* turn Metal fast math off before the first compute kernel ([#28](https://github.com/mac4DSTEM/macTEM/issues/28)) ([3bffd96](https://github.com/mac4DSTEM/macTEM/commit/3bffd96616f740fd91350ce66c914814aa63d6f8))

## v1.0.0 — 2026-10-23

First release. macTEM analyses TEM images, EDS and EELS spectrum images and diffraction patterns on Apple silicon
Macs (macOS 27 at this release). The numbers come from the suite's kits (FormatoKit 0.11.0, DiffractoKit 0.10.0,
ImagoKit 0.7.0, SpectroKit 0.12.0) and the window from MacEMUI 0.3.0; anything not yet checked against known truth says
`validation: none`.

### Added

- **Opening files.** DigitalMicrograph (.dm3, .dm4), Velox (.emd), TIFF and MRC. The file's content decides the room,
  not its extension: an image opens in the Image room, a spectrum image in the EDS or EELS room (a Velox file with a
  HAADF image and a spectrum cube fills both), a single `.msa` spectrum in the EDS room. A room with no data for the
  open files is disabled in the sidebar with a one-line reason.
- **Rooms** in the order the work goes: Prepare, Image, FFT, EDS, EELS, Diffraction and Results (⌘1 to ⌘7).
- **Image room.** Calibration from the file, colormap, contrast window and gamma; zoom (⌘+, ⌘−, ⌘0) with the pixel
  under the pointer in the status line; distances, angles and line profiles measured on the file's pixels; marks saved
  in a session file next to the image.
- **Image stacks.** A multi-page TIFF or ImageJ stack opens frame by frame, read on demand (a 100-frame series shows a
  frame in about 2 MB of memory). ← and → step through the frames, Home and End go to the ends, and "Same contrast for
  every frame" holds the contrast window so brightness drift shows.
- **Particles.** Bright or dark objects found by a threshold in the image's own units, with optional smoothing, 4 or 8
  connectivity and a minimum area; each object outlined with its moments ellipse, a sortable table and a CSV export.
- **FFT room.** The transform of the image or a region with a window (Hann, Hamming, Blackman, Tukey), spots and their
  d-spacings, Find Spots with an editable threshold, distance and count, the radial profile, a masked inverse, and
  Gaussian, band-pass, ABSF and Wiener filters.
- **EDS room.** Velox and GMS spectrum images. Elements from the periodic table or from Auto ID (the published
  AutoEMX/NIST identification loop); net-count, wt%, at% and thickness maps; the pooled Cliff-Lorimer fit with
  computed or typed k-factors and the absorption correction when the file gives the detector geometry and a thickness
  is typed; zeta-factor and cross-section methods. Quantify is the toolbar's verb (⌘↩).
- **EELS room.** Dual-EELS spectrum images with their low loss and core loss. Run aligns the zero-loss peak, maps t/λ
  and fits the chosen edges; the periodic table offers 383 K, L and M edges of 95 elements (the generalised oscillator
  strengths of Segger, Guzzinati and Kohl, bundled; see NOTICE). Background and signal windows can be dragged on the
  spectrum; each edge's intensity carries its 1σ, and an edge at or under 3σ reads "below detection".
- **Regions** in the EDS and EELS rooms: rectangles, ellipses, polygons and lines, each numbered and coloured, with
  their spectra overlaid, a table row per region and line profiles across the maps.
- **Diffraction room.** Any image read as a pattern: a centre (image centre, typed, or a fitted ring's), a scale from a
  ring calibrated against Au, Al or Si (or the file's reciprocal axis, or a typed Δq), fitted rings and clicked spots
  indexed against a standard or an opened CIF, and a readout table and CSV.
- **Results room.** Every measurement of a file in one table, exported as CSV.
- **Exports.** PNG figures with the scale bar, CSV tables, and a method JSON for the spectroscopy rooms.
