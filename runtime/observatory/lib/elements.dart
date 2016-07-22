library observatory_elements;

// Export elements.
export 'package:observatory/src/elements/action_link.dart';
export 'package:observatory/src/elements/class_ref.dart';
export 'package:observatory/src/elements/class_tree.dart';
export 'package:observatory/src/elements/class_view.dart';
export 'package:observatory/src/elements/code_ref.dart';
export 'package:observatory/src/elements/code_view.dart';
export 'package:observatory/src/elements/context_ref.dart';
export 'package:observatory/src/elements/context_view.dart';
export 'package:observatory/src/elements/cpu_profile.dart';
export 'package:observatory/src/elements/debugger.dart';
export 'package:observatory/src/elements/error_view.dart';
export 'package:observatory/src/elements/eval_box.dart';
export 'package:observatory/src/elements/eval_link.dart';
export 'package:observatory/src/elements/field_ref.dart';
export 'package:observatory/src/elements/field_view.dart';
export 'package:observatory/src/elements/flag_list.dart';
export 'package:observatory/src/elements/function_ref.dart';
export 'package:observatory/src/elements/function_view.dart';
export 'package:observatory/src/elements/general_error.dart';
export 'package:observatory/src/elements/heap_map.dart';
export 'package:observatory/src/elements/heap_profile.dart';
export 'package:observatory/src/elements/heap_snapshot.dart';
export 'package:observatory/src/elements/icdata_view.dart';
export 'package:observatory/src/elements/instance_ref.dart';
export 'package:observatory/src/elements/instance_view.dart';
export 'package:observatory/src/elements/instructions_view.dart';
export 'package:observatory/src/elements/io_view.dart';
export 'package:observatory/src/elements/isolate_reconnect.dart';
export 'package:observatory/src/elements/isolate_ref.dart';
export 'package:observatory/src/elements/isolate_summary.dart';
export 'package:observatory/src/elements/isolate_view.dart';
export 'package:observatory/src/elements/json_view.dart';
export 'package:observatory/src/elements/library_ref.dart';
export 'package:observatory/src/elements/library_view.dart';
export 'package:observatory/src/elements/logging.dart';
export 'package:observatory/src/elements/megamorphiccache_view.dart';
export 'package:observatory/src/elements/metrics.dart';
export 'package:observatory/src/elements/nav_bar.dart';
export 'package:observatory/src/elements/object_common.dart';
export 'package:observatory/src/elements/object_view.dart';
export 'package:observatory/src/elements/objectpool_view.dart';
export 'package:observatory/src/elements/objectstore_view.dart';
export 'package:observatory/src/elements/observatory_application.dart';
export 'package:observatory/src/elements/observatory_element.dart';
export 'package:observatory/src/elements/persistent_handles.dart';
export 'package:observatory/src/elements/ports.dart';
export 'package:observatory/src/elements/script_inset.dart';
export 'package:observatory/src/elements/script_ref.dart';
export 'package:observatory/src/elements/script_view.dart';
export 'package:observatory/src/elements/service_ref.dart';
export 'package:observatory/src/elements/service_view.dart';
export 'package:observatory/src/elements/sliding_checkbox.dart';
export 'package:observatory/src/elements/timeline_page.dart';
export 'package:observatory/src/elements/vm_connect.dart';
export 'package:observatory/src/elements/vm_ref.dart';
export 'package:observatory/src/elements/vm_view.dart';

import 'dart:async';

import 'package:observatory/src/elements/curly_block.dart';
import 'package:observatory/src/elements/curly_block_wrapper.dart';
import 'package:observatory/src/elements/nav/bar.dart';
import 'package:observatory/src/elements/nav/isolate_menu.dart';
import 'package:observatory/src/elements/nav/isolate_menu_wrapper.dart';
import 'package:observatory/src/elements/nav/menu.dart';
import 'package:observatory/src/elements/nav/menu_wrapper.dart';
import 'package:observatory/src/elements/nav/menu_item.dart';
import 'package:observatory/src/elements/nav/menu_item_wrapper.dart';
import 'package:observatory/src/elements/nav/refresh.dart';
import 'package:observatory/src/elements/nav/refresh_wrapper.dart';
import 'package:observatory/src/elements/nav/top_menu.dart';
import 'package:observatory/src/elements/nav/top_menu_wrapper.dart';
import 'package:observatory/src/elements/view_footer.dart';

export 'package:observatory/src/elements/helpers/rendering_queue.dart';

export 'package:observatory/src/elements/curly_block.dart';
export 'package:observatory/src/elements/nav/bar.dart';
export 'package:observatory/src/elements/nav/isolate_menu.dart';
export 'package:observatory/src/elements/nav/menu.dart';
export 'package:observatory/src/elements/nav/menu_item.dart';
export 'package:observatory/src/elements/nav/refresh.dart';
export 'package:observatory/src/elements/nav/top_menu.dart';
export 'package:observatory/src/elements/view_footer.dart';

// Even though this function does not invoke any asynchronous operation
// it is marked as async to allow future backward compatible changes.
Future initElements() async {
  CurlyBlockElement.tag.ensureRegistration();
  CurlyBlockElementWrapper.tag.ensureRegistration();
  NavBarElement.tag.ensureRegistration();
  NavIsolateMenuElement.tag.ensureRegistration();
  NavIsolateMenuElementWrapper.tag.ensureRegistration();
  NavMenuElement.tag.ensureRegistration();
  NavMenuElementWrapper.tag.ensureRegistration();
  NavMenuItemElement.tag.ensureRegistration();
  NavMenuItemElementWrapper.tag.ensureRegistration();
  NavRefreshElement.tag.ensureRegistration();
  NavRefreshElementWrapper.tag.ensureRegistration();
  NavTopMenuElement.tag.ensureRegistration();
  NavTopMenuElementWrapper.tag.ensureRegistration();
  ViewFooterElement.tag.ensureRegistration();
}
