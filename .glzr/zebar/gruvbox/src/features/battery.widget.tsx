import { useProviders } from "@providers/index";
import { GroupItem } from "@components/group.component";
import { createMemo, Show, Switch, Match } from "solid-js";
import {
  FaSolidBatteryEmpty,
  FaSolidBatteryQuarter,
  FaSolidBatteryHalf,
  FaSolidBatteryFull,
} from "solid-icons/fa";
import { RiDeviceBatteryChargeLine } from "solid-icons/ri";

/**
 * Displays the current battery charge percentage and charging status.
 * The icon changes based on the current charge level, and a charging
 * indicator is shown when the device is plugged in.
 */
export function BatteryWidget() {
  const providers = useProviders();

  const chargePercent = createMemo(
    () => providers.battery?.chargePercent ?? 0,
  );
  const isCharging = createMemo(
    () => providers.battery?.isCharging ?? false,
  );

  return (
    <Show when={providers.battery}>
      <GroupItem class="flex items-center gap-1">
        <Switch
          fallback={
            <FaSolidBatteryFull class="w-4 h-4 text-gruvbox-mint" />
          }
        >
          <Match when={isCharging()}>
            <RiDeviceBatteryChargeLine class="w-4 h-4 text-gruvbox-mint" />
          </Match>
          <Match when={!isCharging() && chargePercent() <= 10}>
            <FaSolidBatteryEmpty class="w-4 h-4 text-gruvbox-cherry" />
          </Match>
          <Match when={!isCharging() && chargePercent() <= 30}>
            <FaSolidBatteryQuarter class="w-4 h-4 text-gruvbox-watermelon" />
          </Match>
          <Match when={!isCharging() && chargePercent() <= 55}>
            <FaSolidBatteryHalf class="w-4 h-4 text-gruvbox-peach" />
          </Match>
          <Match when={!isCharging() && chargePercent() <= 80}>
            <FaSolidBatteryFull class="w-4 h-4 text-gruvbox-lavender" />
          </Match>
        </Switch>
        {Math.round(chargePercent())}%
      </GroupItem>
    </Show>
  );
}
