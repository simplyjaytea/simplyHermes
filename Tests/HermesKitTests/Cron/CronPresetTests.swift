import HermesKit
import Testing

@Suite struct CronPresetTests {
    @Test func presetsBuildFiveFieldExpressions() {
        #expect(CronPreset.hourly.expression() == "0 * * * *")
        #expect(CronPreset.daily.expression(hour: 9, minute: 5) == "5 9 * * *")
        #expect(CronPreset.weekdays.expression(hour: 7, minute: 30) == "30 7 * * 1-5")
        #expect(CronPreset.weekly.expression(hour: 8, minute: 0, weekday: 3) == "0 8 * * 3")
        #expect(CronPreset.monthly.expression(hour: 12, minute: 15, dayOfMonth: 15) == "15 12 15 * *")
    }

    @Test func presetValuesAreClampedAndEveryPresetIsValidCron() {
        #expect(CronPreset.daily.expression(hour: 25, minute: -3) == "0 23 * * *")
        #expect(CronPreset.weekly.expression(weekday: 9) == "0 9 * * 6")
        #expect(CronPreset.monthly.expression(dayOfMonth: 0) == "0 9 1 * *")
        for preset in CronPreset.allCases {
            #expect(CronExpression.validate(preset.expression()) == nil, "\(preset) must produce valid cron")
        }
    }

    @Test func matchingReadsBackOnlyTheTextAPresetWrites() {
        #expect(CronPreset.matching("5 9 * * *") == CronPresetSettings(preset: .daily, hour: 9, minute: 5))
        #expect(CronPreset.matching("30 7 * * 1-5") == CronPresetSettings(preset: .weekdays, hour: 7, minute: 30))
        #expect(
            CronPreset.matching("0 8 * * 3") == CronPresetSettings(preset: .weekly, hour: 8, minute: 0, weekday: 3))
        #expect(
            CronPreset.matching("15 12 15 * *")
                == CronPresetSettings(preset: .monthly, hour: 12, minute: 15, dayOfMonth: 15))
        #expect(CronPreset.matching("0 * * * *") == CronPresetSettings(preset: .hourly))
        // Valid cron that no preset writes stays in the custom field.
        #expect(CronPreset.matching("00 9 * * *") == nil)
        #expect(CronPreset.matching("0 9 * * 1,3") == nil)
        #expect(CronPreset.matching("0 9 * jan *") == nil)
        #expect(CronPreset.matching("0 9 * * 7") == nil)
        #expect(CronPreset.matching("every 2h") == nil)
    }

    @Test func settingsRoundTripThroughTheirExpression() {
        for preset in CronPreset.allCases {
            let settings = CronPresetSettings(preset: preset, hour: 6, minute: 45, weekday: 4, dayOfMonth: 20)
            #expect(CronPreset.matching(settings.expression)?.preset == preset, "\(preset) must read back as itself")
            #expect(CronPreset.matching(settings.expression)?.expression == settings.expression)
        }
    }
}
