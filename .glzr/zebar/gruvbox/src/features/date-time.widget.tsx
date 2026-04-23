import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function DateTimeWidget() {
  const providers = useProviders();

  return <GroupItem class="text-gruvbox-mint bold">{providers.date?.formatted}</GroupItem>;
}
