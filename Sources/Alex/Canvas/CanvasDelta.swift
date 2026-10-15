import Foundation

/// What one change did to a canvas, by id (PLAN.md, revision 52): the
/// nodes and edges it added, changed or took away, each with where it
/// stood, and the order of the rest when the change reordered them. An
/// undo applies the inverse to the canvas as it is *now*, Excalidraw's
/// way (its `ElementsDelta`), so a card the door or another app added
/// since is left alone; putting back the whole document from before the
/// change, as undo did until then, deleted it.
struct CanvasDelta: Equatable {
    struct Change<Item: Equatable>: Equatable {
        var before: Item?
        var after: Item?
        /// Where it stood in the list before and after, for putting it
        /// back where it was.
        var beforeIndex: Int?
        var afterIndex: Int?

        var inverse: Change {
            Change(before: after, after: before, beforeIndex: afterIndex, afterIndex: beforeIndex)
        }
    }

    /// A change of z-order among the items both sides hold: every id in
    /// order, before and after.
    struct Order: Equatable {
        var before: [String]
        var after: [String]
    }

    var nodes: [String: Change<CanvasNode>] = [:]
    var edges: [String: Change<CanvasEdge>] = [:]
    var nodeOrder: Order?
    var edgeOrder: Order?
    /// The canvas's own keys besides its nodes and edges, before and after.
    var extra: Change<[String: JSONValue]>?

    init(from a: CanvasDocument, to b: CanvasDocument) {
        (nodes, nodeOrder) = Self.diff(a.nodes, b.nodes)
        (edges, edgeOrder) = Self.diff(a.edges, b.edges)
        if a.extra != b.extra { extra = Change(before: a.extra, after: b.extra) }
    }

    private init() {}

    var isEmpty: Bool {
        nodes.isEmpty && edges.isEmpty && nodeOrder == nil && edgeOrder == nil && extra == nil
    }

    var inverse: CanvasDelta {
        var back = CanvasDelta()
        back.nodes = nodes.mapValues(\.inverse)
        back.edges = edges.mapValues(\.inverse)
        back.nodeOrder = nodeOrder.map { Order(before: $0.after, after: $0.before) }
        back.edgeOrder = edgeOrder.map { Order(before: $0.after, after: $0.before) }
        back.extra = extra?.inverse
        return back
    }

    /// The change made again on `doc`: each id it touched set to what the
    /// change left, everything else as `doc` has it.
    func apply(to doc: CanvasDocument) -> CanvasDocument {
        var next = doc
        next.nodes = Self.patch(doc.nodes, nodes, order: nodeOrder)
        next.edges = Self.patch(doc.edges, edges, order: edgeOrder)
        if let extra, let after = extra.after { next.extra = after }
        return next
    }

    // MARK: - Lists by id

    private static func diff<Item: Identifiable & Equatable>(_ a: [Item], _ b: [Item])
        -> ([String: Change<Item>], Order?) where Item.ID == String {
        let beforeIndex = Dictionary(a.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let afterIndex = Dictionary(b.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [String: Change<Item>] = [:]
        for (id, i) in beforeIndex where afterIndex[id].map({ b[$0] != a[i] }) ?? true {
            changes[id] = Change(before: a[i], after: afterIndex[id].map { b[$0] },
                                 beforeIndex: i, afterIndex: afterIndex[id])
        }
        for (id, j) in afterIndex where beforeIndex[id] == nil {
            changes[id] = Change(before: nil, after: b[j], beforeIndex: nil, afterIndex: j)
        }
        // Order counts only among the items on both sides: an add or a
        // removal is not a reorder.
        let kept = Set(beforeIndex.keys).intersection(afterIndex.keys)
        let order = a.map(\.id).filter(kept.contains) == b.map(\.id).filter(kept.contains)
            ? nil : Order(before: a.map(\.id), after: b.map(\.id))
        return (changes, order)
    }

    private static func patch<Item: Identifiable & Equatable>(
        _ list: [Item], _ changes: [String: Change<Item>], order: Order?) -> [Item] where Item.ID == String {
        var items = list.filter { item in changes[item.id].map { $0.after != nil } ?? true }
        for i in items.indices {
            if let after = changes[items[i].id]?.after { items[i] = after }
        }
        let present = Set(items.map(\.id))
        let arriving = changes.values
            .filter { $0.after != nil }
            .compactMap { change -> (Int, Item)? in
                guard let item = change.after, !present.contains(item.id) else { return nil }
                return (change.afterIndex ?? Int.max, item)
            }
            .sorted { $0.0 < $1.0 }
        for (index, item) in arriving {
            items.insert(item, at: min(index, items.count))
        }
        guard let order else { return items }
        // The ids the order names go back into the slots they hold now, in
        // its order; anything it does not name keeps its place.
        let rank = Dictionary(order.after.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = items.indices.filter { rank[items[$0].id] != nil }
        let ranked = slots.map { items[$0] }.sorted { rank[$0.id]! < rank[$1.id]! }
        for (slot, item) in zip(slots, ranked) { items[slot] = item }
        return items
    }
}
