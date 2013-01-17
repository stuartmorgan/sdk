// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_CODE_DESCRIPTORS_H_
#define VM_CODE_DESCRIPTORS_H_

#include "vm/code_generator.h"
#include "vm/globals.h"
#include "vm/growable_array.h"
#include "vm/object.h"

namespace dart {

class DescriptorList : public ZoneAllocated {
 public:
  struct PcDesc {
    intptr_t pc_offset;        // PC offset value of the descriptor.
    PcDescriptors::Kind kind;  // Descriptor kind (kDeopt, kOther).
    intptr_t deopt_id;         // Deoptimization id.
    intptr_t data;             // Token position or deopt rason.
    intptr_t try_index;        // Try block index of PC or deopt array index.
    void SetTokenPos(intptr_t value) { data = value; }
    intptr_t TokenPos() const { return data; }
    void SetDeoptReason(DeoptReasonId value) { data = value; }
    DeoptReasonId DeoptReason() const {
      return static_cast<DeoptReasonId>(data);
    }
  };

  explicit DescriptorList(intptr_t initial_capacity) : list_(initial_capacity) {
  }
  ~DescriptorList() { }

  intptr_t Length() const {
    return list_.length();
  }

  intptr_t PcOffset(int index) const {
    return list_[index].pc_offset;
  }
  PcDescriptors::Kind Kind(int index) const {
    return list_[index].kind;
  }
  intptr_t DeoptId(int index) const {
    return list_[index].deopt_id;
  }
  intptr_t TokenPos(int index) const {
    return list_[index].TokenPos();
  }
  DeoptReasonId DeoptReason(int index) const {
    return list_[index].DeoptReason();
  }
  intptr_t TryIndex(int index) const {
    return list_[index].try_index;
  }

  void AddDescriptor(PcDescriptors::Kind kind,
                     intptr_t pc_offset,
                     intptr_t deopt_id,
                     intptr_t token_index,
                     intptr_t try_index);

  RawPcDescriptors* FinalizePcDescriptors(uword entry_point);

 private:
  GrowableArray<struct PcDesc> list_;
  DISALLOW_COPY_AND_ASSIGN(DescriptorList);
};


class StackmapTableBuilder : public ZoneAllocated {
 public:
  explicit StackmapTableBuilder()
      : stack_map_(Stackmap::ZoneHandle()),
        list_(GrowableObjectArray::ZoneHandle(
            GrowableObjectArray::New(Heap::kOld))) { }
  ~StackmapTableBuilder() { }

  void AddEntry(intptr_t pc_offset,
                BitmapBuilder* bitmap,
                intptr_t register_bit_count);

  bool Verify();

  RawArray* FinalizeStackmaps(const Code& code);

 private:
  intptr_t Length() const { return list_.Length(); }
  RawStackmap* MapAt(int index) const;

  Stackmap& stack_map_;
  GrowableObjectArray& list_;
  DISALLOW_COPY_AND_ASSIGN(StackmapTableBuilder);
};


class ExceptionHandlerList : public ZoneAllocated {
 public:
  struct HandlerDesc {
    intptr_t outer_try_index;  // Try block in which this try block is nested.
    intptr_t pc_offset;        // Handler PC offset value.
    const Array* handler_types;   // Catch clause guards.
  };

  ExceptionHandlerList() : list_() {}

  intptr_t Length() const {
    return list_.length();
  }

  void AddPlaceHolder() {
    struct HandlerDesc data;
    data.outer_try_index = -1;
    data.pc_offset = -1;
    data.handler_types = NULL;
    list_.Add(data);
  }

  void AddHandler(intptr_t try_index,
                  intptr_t outer_try_index,
                  intptr_t pc_offset,
                  const Array& handler_types) {
    ASSERT(try_index >= 0);
    while (Length() <= try_index) {
      AddPlaceHolder();
    }
    list_[try_index].outer_try_index = outer_try_index;
    list_[try_index].pc_offset = pc_offset;
    ASSERT(handler_types.IsZoneHandle());
    list_[try_index].handler_types = &handler_types;
  }

  RawExceptionHandlers* FinalizeExceptionHandlers(uword entry_point) {
    intptr_t num_handlers = Length();
    const ExceptionHandlers& handlers =
        ExceptionHandlers::Handle(ExceptionHandlers::New(num_handlers));
    for (intptr_t i = 0; i < num_handlers; i++) {
      // Assert that every element in the array has been initialized.
      ASSERT(list_[i].handler_types != NULL);
      handlers.SetHandlerInfo(i,
                              list_[i].outer_try_index,
                              (entry_point + list_[i].pc_offset));
      handlers.SetHandledTypes(i, *list_[i].handler_types);
    }
    return handlers.raw();
  }

 private:
  GrowableArray<struct HandlerDesc> list_;
  DISALLOW_COPY_AND_ASSIGN(ExceptionHandlerList);
};

}  // namespace dart

#endif  // VM_CODE_DESCRIPTORS_H_
