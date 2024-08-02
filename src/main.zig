const std = @import("std");
const math = std.math;

const LabelProb = [256]f64;
const InputData = struct { 
    level: []const u8,
    lang: []const u8,
    tweets: []const u8,
    phd: []const u8,
};
const InputWithLabel = struct { data: InputData, result: bool };
const input_data = [_]InputWithLabel{
    .{ .data = .{ .level = "Senior", .lang = "Java", .tweets = "no", .phd = "no" }, .result = false },
    .{ .data = .{ .level = "Senior", .lang = "Java", .tweets = "no", .phd = "yes" }, .result = false },
    .{ .data = .{ .level = "Mid", .lang = "Python", .tweets = "no", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Junior", .lang = "Python", .tweets = "no", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Junior", .lang = "R", .tweets = "yes", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Junior", .lang = "R", .tweets = "yes", .phd = "yes" }, .result = false },
    .{ .data = .{ .level = "Mid", .lang = "R", .tweets = "yes", .phd = "yes" }, .result = true },
    .{ .data = .{ .level = "Senior", .lang = "Python", .tweets = "no", .phd = "no" }, .result = false },
    .{ .data = .{ .level = "Senior", .lang = "R", .tweets = "yes", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Junior", .lang = "Python", .tweets = "yes", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Senior", .lang = "Python", .tweets = "yes", .phd = "yes" }, .result = true },
    .{ .data = .{ .level = "Mid", .lang = "Python", .tweets = "no", .phd = "yes" }, .result = true },
    .{ .data = .{ .level = "Mid", .lang = "Java", .tweets = "yes", .phd = "no" }, .result = true },
    .{ .data = .{ .level = "Junior", .lang = "Python", .tweets = "no", .phd = "yes" }, .result = false },
};

pub fn main() !void {
    std.debug.print("hello world\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tree = try buildTreeId3(allocator, &input_data,null);
    defer {
        tree.deinit();
        allocator.destroy(tree);
    }
    const input_value= InputData{.level = "Junior", .lang = "Java", .tweets="yes", .phd = "yes"};
    const final_result: bool = classify(tree, input_value);

    std.debug.print("Input Data = \n",.{});
    inline for (std.meta.fields(@TypeOf(input_value))) |f| {
        std.debug.print(f.name ++ " {c}\n", .{@as(f.type, @field(input_value, f.name))});
    }    
    std.debug.print("Label = {any}\n", .{final_result});

}

fn classify(tree: *Tree, input:InputData) bool {
    var current_node = tree;

    while(true){
        if (current_node.attribute == null) {
            if (current_node.subtrees.get("None")) |none_value| {
                return switch (none_value) {
                    .leaf => |leaf_value| leaf_value,
                    .subtree => unreachable, 
                };
            } else {
                unreachable; 
            }
        }        
        const attribute = current_node.attribute.?;
        const subtree_key = switch (attribute[0]) {
            'l' => if (std.mem.eql(u8, attribute, "level")) input.level else input.lang,
            't' => input.tweets,
            'p' => input.phd,
            else=> unreachable,
        };
        if(current_node.subtrees.get(subtree_key)) |subtree_value| {
            switch (subtree_value) {
                .leaf => |leaf_value| return leaf_value,
                .subtree => |new_node| current_node = new_node,
            }

        }else if (current_node.subtrees.get("None")) |default_value| {
            switch (default_value) {
                .leaf => |leaf_value| return leaf_value,
                .subtree => |next_node| current_node = next_node,
            }
        } else {
            unreachable;
        }
    }
}


fn buildTreeId3(allocator:std.mem.Allocator,inputs:[]const InputWithLabel,split_candidates:?std.ArrayList([]const u8))!*Tree {
    var candidates:std.ArrayList([]const u8)= undefined;
    if (split_candidates) |sc|{
        candidates = sc; 
    }else {
        candidates = std.ArrayList([]const u8).init(std.heap.page_allocator);
        const data_fields = @TypeOf(inputs[0].data);
        const field_values = std.meta.fieldNames(data_fields);
        for (field_values) |field_value|{
            try candidates.append(field_value);
        }
    }
    defer if (split_candidates == null) candidates.deinit();

    const num_inputs = inputs.len;
    var num_trues:u8 = 0;
    for (inputs) |input|{
        if(input.result == true){
            num_trues +=1;
        }
    }
    const num_falses = num_inputs - num_trues;
    var node = try allocator.create(Tree);
    errdefer allocator.destroy(node);
    node.* = Tree.init(allocator);
    errdefer node.deinit();

    if (num_trues == 0 or num_falses == 0 or candidates.items.len == 0) {
        try node.subtrees.put("None", .{ .leaf = num_trues > num_falses });
        return node;
    }

    if (candidates.items.len == 0){
        try node.subtrees.put("None", .{ .leaf = num_trues >= num_falses });
        return node;
    }


    var best_attribute: []const u8 = undefined;
    var min_entropy:f64 = 1.0;
    for (candidates.items) |item| {
        const entropy_ret:f64 = try partitionEntropyBy(allocator, inputs, item);
        if(entropy_ret < min_entropy){
            min_entropy = entropy_ret;
            best_attribute = item;
        }
    }
    node.attribute = best_attribute;
    const partitions = try partitionBy(allocator, inputs, best_attribute);
    defer {
        partitions.deinit();
        allocator.destroy(partitions);
    }

    var new_candidates = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer new_candidates.deinit();
    for (candidates.items) |candidate| {
        if (!std.mem.eql(u8,candidate, best_attribute)){
            try new_candidates.append(candidate);
        }
    }

    var it = partitions.map.iterator();
    while (it.next()) |entry| {
        const subtree = try buildTreeId3(allocator, entry.value_ptr.items, new_candidates);
        errdefer {
            subtree.deinit();
            allocator.destroy(subtree);
        }
        try node.subtrees.put(entry.key_ptr.*, .{.subtree=subtree});
    }


    try node.subtrees.put("None",  .{.leaf=num_trues > num_falses});

    return node;


}


fn partitionEntropyBy(allocator: std.mem.Allocator, inputs: []const InputWithLabel, attributes: []const u8) !f64 {
    const partitions = try partitionBy(allocator, inputs, attributes);
    defer {
        partitions.deinit();
        allocator.destroy(partitions);
    }
    return partitionEntropy(partitions);

}

fn partitionBy(allocator: std.mem.Allocator, inputs: []const InputWithLabel, attributes: []const u8) !*DefaultDict {
    var groups = try allocator.create(DefaultDict);
    groups.* = DefaultDict.init(allocator);
    for (inputs) |input| {
        const key = switch (attributes[0]) {
            'l' => if (std.mem.eql(u8, attributes, "level")) input.data.level else input.data.lang,
            't' => input.data.tweets,
            'p' => input.data.phd,
            else => unreachable,
        };
        try (try groups.get(key)).append(input);


    }
    return groups;

}
const TreeValue = union(enum) {
    leaf: bool,
    subtree: *Tree,
};
const Tree = struct {
    attribute: ?[]const u8,
    subtrees: std.StringHashMap(TreeValue),

    pub fn init(allocator: std.mem.Allocator) Tree {
        return .{
            .attribute = null,
            .subtrees = std.StringHashMap(TreeValue).init(allocator),
        };
    }
    fn deinit(self: *Tree) void {
        var it = self.subtrees.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .subtree => |subtree| {
                    subtree.deinit();
                    self.subtrees.allocator.destroy(subtree);
                },
                .leaf => {},
            }
        }
        self.subtrees.deinit();
    }

};

const DefaultDict = struct {
    map: std.StringHashMap(std.ArrayList(InputWithLabel)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DefaultDict {

        return .{
            .map = std.StringHashMap(std.ArrayList(InputWithLabel)).init(allocator),
            .allocator = allocator,
        };
    }
    fn deinit(self: *DefaultDict) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.map.deinit();
    }
    fn get(self: *DefaultDict, key: []const u8) !*std.ArrayList(InputWithLabel){
        const result = try self.map.getOrPut(key);
        if (!result.found_existing){
            result.value_ptr.* = std.ArrayList(InputWithLabel).init(self.allocator);
        }  
        return result.value_ptr;
    }   
};



fn partitionEntropy(partitions: *DefaultDict) f64 {
    var total_count: f64 = undefined;
    var total_sum: f64 = undefined;
    var it = partitions.map.iterator();

    while (it.next()) |entry| {
        const subset = entry.value_ptr.items;
        total_count+=@as(f64,@floatFromInt(subset.len));
    }
    it = partitions.map.iterator();
    while (it.next()) |entry| {
        const subset = entry.value_ptr.items;
        total_sum+=(dataEntropy(subset) * @as(f64, @floatFromInt(subset.len)))/total_count;    
    }
    return total_sum;
}

fn dataEntropy(inputs: []const InputWithLabel) f64 {
    const class_probs: LabelProb = classProbs(inputs);
    const data_entropy: f64 = entropy(class_probs);
    return data_entropy;

}

fn entropy(x: LabelProb) f64 {
    var sum : f64 = 0;

    for (x) |p| {
        if (p>0){
            sum -= p*math.log2(p);
        }       
    }
    return sum;
} 


fn classProbs(x: []const InputWithLabel) LabelProb {
    var result = std.mem.zeroes(LabelProb);
    const total_count:f64 =@floatFromInt(x.len);
    for (x) |input| {
        const index = @intFromBool(input.result);
        result[index] += 1;
    }
    for (result, 0..) |count, i| {
        if (count > 0) {
            result[i] = count / total_count;
        }
    }
    return result;
}





fn printDefault(input: DefaultDict) !void {
    var it = input.map.iterator();
    while (it.next()) |entry| {
        std.debug.print("Level: {s}, Count: {}\n", .{ entry.key_ptr.*, @intFromBool(entry.value_ptr.items[1].result) });

        //    std.debug.print("{}\n", .{ entry.value_ptr.items[0].result });
    }
}

fn printProbs(x: LabelProb) void {

    for (x) |a| {
        if(a==0) continue;
        std.debug.print("{d},", .{a});
    }
    std.debug.print("\n", .{});
}

