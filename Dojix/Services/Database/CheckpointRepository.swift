import Foundation
import GRDB

/// Repository for CRUD operations on strategy checkpoints
struct CheckpointRepository: Sendable {
    let database: DatabaseManager

    /// Insert a new checkpoint
    @discardableResult
    func insert(_ checkpoint: StrategyCheckpoint) throws -> StrategyCheckpoint {
        var cp = checkpoint
        try database.dbQueue.write { db in
            try cp.insert(db)
        }
        return cp
    }

    /// Fetch all checkpoints ordered by date descending
    func fetchAll() throws -> [StrategyCheckpoint] {
        try database.dbQueue.read { db in
            try StrategyCheckpoint
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    /// Delete a checkpoint by ID
    func delete(id: Int64) throws {
        try database.dbQueue.write { db in
            _ = try StrategyCheckpoint.deleteOne(db, id: id)
        }
    }

    /// Observe all checkpoints for live updates. Main-actor isolated because GRDB
    /// delivers changes on the main queue by default (same as TradeRepository).
    @MainActor
    func observeAll(
        onError: @escaping @Sendable (Error) -> Void,
        onChange: @escaping @Sendable ([StrategyCheckpoint]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try StrategyCheckpoint
                .order(Column("date").desc)
                .fetchAll(db)
        }
        return observation.start(
            in: database.dbQueue,
            onError: onError,
            onChange: onChange
        )
    }
}
