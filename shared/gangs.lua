-- label / grade.name are the English names; label_ar / grade.name_ar the Arabic ones.
-- WShared.JobLabel(gang) / WShared.GradeName(gang) pick the one for the player's language.
WGangs = {
	['none'] = {
		label = 'No Gang',
		label_ar = "بدون عصابة",
		grades = {
            [0] = {
                name = 'Unaffiliated',
                name_ar = "غير منتسب"
            }
        }
	},
    ['example'] = {
		label = "Example Gang",
		label_ar = "عصابة تجريبية",
		grades = {
            [0] = {
                name = 'Recruit',
                name_ar = "مستجد"
            },
			[1] = {
                name = 'Enforcer',
                name_ar = "منفّذ"
            },
			[2] = {
                name = 'Shot Caller',
                name_ar = "صاحب القرار"
            },
			[3] = {
                name = 'Boss',
                name_ar = "الزعيم",
				isboss = true
            },
        }
	},
}
