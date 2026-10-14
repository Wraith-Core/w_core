WShared = WShared or {}

WShared.ForceJobDefaultDutyAtLogin = true -- true: Force duty state to jobdefaultDuty | false: set duty state from database last saved

-- label / grade.name are the English names; label_ar / grade.name_ar the Arabic ones.
-- WShared.JobLabel(job) / WShared.GradeName(job) pick the one for the player's language.
WJobs = {
	['unemployed'] = {
		label = 'Civilian',
		label_ar = "مدني",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = {
                name = 'Freelancer',
                name_ar = "عامل حر",
                payment = 10
            },
        },
	},
	['railroad'] = {
		label = 'Railroad',
		label_ar = "السكة الحديد",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = {
                name = 'Conductor',
                name_ar = "قاطع تذاكر",
                payment = 25
            },
			[1] = {
                name = 'Driver',
                name_ar = "سائق قطار",
                payment = 50
            },
			[2] = {
                name = 'Station Manager',
                name_ar = "مدير المحطة",
				isboss = true,
                payment = 75
            },
        },
	},
	['police'] = {
		label = 'Law Enforcement',
		label_ar = "الشرطة",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = {
                name = 'Recruit',
                name_ar = "مستجد",
                payment = 50
            },
			[1] = {
                name = 'Officer',
                name_ar = "ضابط",
                payment = 75
            },
			[2] = {
                name = 'Sergeant',
                name_ar = "رقيب",
                payment = 100
            },
			[3] = {
                name = 'Lieutenant',
                name_ar = "ملازم",
                payment = 125
            },
			[4] = {
                name = 'Chief',
                name_ar = "قائد الشرطة",
				isboss = true,
                payment = 150
            },
        },
	},
	-- ★ 2026-10-14: the doctors are w_medic's (it replaced w_ambulancejob). Its job is 'doctor' and
	-- these are its ranks (w_medic config.lua Config.DoctorRanks: the same grades, names and
	-- salaries -- keep both in step). `payment` is the paycheck, handed every
	-- WConfig.Money.PayCheckTimeOut minutes while on duty (w_medic's own payroll is off here). The
	-- deputy and the minister hire, promote and dismiss doctors at the Valentine desk (w_medic).
	['doctor'] = {
		label = 'Doctors',
		label_ar = "الأطباء",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = { name = 'Trainee Doctor', name_ar = "طبيب متدرب", payment = 10 },
            [1] = { name = 'Experienced Doctor', name_ar = "طبيب متمرس", payment = 25 },
            [2] = { name = 'Distinguished Doctor', name_ar = "طبيب إمتياز", payment = 35 },
            [3] = { name = 'Doctor', name_ar = "دكتور", payment = 50 },
            [4] = { name = 'Deputy Minister of Health', name_ar = "نائب وزير الصحة", isboss = true, payment = 100 },
            [5] = { name = 'Minister of Health', name_ar = "وزير الصحة", isboss = true, payment = 100 },
        },
	},
	['judge'] = {
		label = 'Honorary',
		label_ar = "القضاء",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = {
                name = 'Judge',
                name_ar = "قاضي",
                payment = 100
            },
        },
	},
	['lawyer'] = {
		label = 'Law Firm',
		label_ar = "مكتب المحاماة",
		defaultDuty = true,
		offDutyPay = false,
		grades = {
            [0] = {
                name = 'Associate',
                name_ar = "محامي",
                payment = 50
            },
        },
	}
}

-- The installed workshop uses this job for full weapon customization.
WJobs.gunsmith = WJobs.gunsmith or {
    label = 'Gunsmith', label_ar = 'حدّاد الأسلحة', defaultDuty = true, offDutyPay = false,
    grades = {
        [0] = {name = 'Gunsmith', name_ar = 'حدّاد أسلحة', payment = 0},
        [1] = {name = 'Master Gunsmith', name_ar = 'كبير الحدّادين', payment = 0, isboss = true},
    },
}
