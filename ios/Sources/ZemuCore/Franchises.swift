import Foundation

/**
 * Franchises (TMDB collections, e.g. "Harry Potter Collection") for the Home and Movies pages.
 * Each seed movie's collection is looked up once per session, and each collection's movies are
 * resolved to playable titles through the metadata addons. Needs a TMDB key.
 */
@MainActor
public final class Franchises {
    public struct Franchise: Sendable {
        public let id: Int64
        public let name: String
        public let movies: [Meta]
    }

    /** Seed movies looked up per call, and movies resolved per collection. */
    private static let seedLimit = 24
    private static let movieLimit = 14

    private let tmdb: Tmdb
    private let addons: AddonRepository
    private var checkedSeeds: Set<String> = []
    private var collectionOfSeed: [String: Int64] = [:]
    private var fetched: Set<Int64> = []
    private var known: [Int64: Franchise] = [:]

    public init(tmdb: Tmdb, addons: AddonRepository) {
        self.tmdb = tmdb
        self.addons = addons
    }

    /** Franchises the seed movies belong to, in seed order, each with at least two movies. */
    public func find(seeds: [Meta]) async -> [Franchise] {
        guard tmdb.enabled else { return [] }
        let batch = Array(seeds.filter { $0.type == "movie" && !checkedSeeds.contains($0.id) }.prefix(Self.seedLimit))
        // A failed lookup isn't remembered, so the seed is tried again on the next call.
        let found = await concurrentMap(batch) { m -> (ok: Bool, c: TmdbCollection?) in
            do { return (true, try await self.tmdb.collection(for: m)) } catch { return (false, nil) }
        }
        var pending: [Int64: TmdbCollection] = [:]
        for (m, r) in zip(batch, found) where r.ok {
            checkedSeeds.insert(m.id)
            if let c = r.c {
                collectionOfSeed[m.id] = c.id
                pending[c.id] = c
            }
        }
        let todo = pending.values.filter { !fetched.contains($0.id) }
        let built = await concurrentMap(todo) { c in await self.build(c) }
        for (c, f) in zip(todo, built) {
            fetched.insert(c.id)
            if f.movies.count >= 2 { known[c.id] = f }
        }
        var order: [Int64] = []
        for m in seeds {
            if let cid = collectionOfSeed[m.id], !order.contains(cid) { order.append(cid) }
        }
        return order.compactMap { known[$0] }
    }

    private func build(_ c: TmdbCollection) async -> Franchise {
        let metas = await concurrentMap(Array(c.parts.prefix(Self.movieLimit))) { part in await self.movie(for: part) }
        return Franchise(id: c.id, name: c.name, movies: metas.compactMap { $0 })
    }

    private func movie(for part: TmdbCredit) async -> Meta? {
        guard let imdb = try? await tmdb.imdbIdFor(part) else { return nil }
        return await addons.meta(type: "movie", id: imdb)
    }
}
