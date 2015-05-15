part of elastic_dart;

final _responseDecoder = const Utf8Decoder().fuse(const JsonDecoder());

class ElasticSearch {
  /// The address of the ElasticSearch REST API.
  final String host;

  ElasticSearch([this.host = 'http://127.0.0.1:9200']);

  /// Creates an index with the given [name] with optional [settings].
  ///
  /// Examples:
  /// ```dart
  ///   // Creates an index called "movie-index" without any settings.
  ///   await elasticsearch.createIndex('movie-index');
  ///
  ///   // Creates an index called "movie-index" with 3 shards, each with 2 replicas.
  ///   await elasticsearch.createIndex('movie-index', {
  ///     "settings" : {
  ///       "number_of_shards" : 3,
  ///       "number_of_replicas" : 2
  ///       }
  ///    });
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/indices-create-index.html)
  Future createIndex(String name, {Map settings: const {}, bool throwIfExists: true}) async {
    try {
      return await _put(name, settings);
    } on ElasticSearchException catch(e) {
      if (e.message.startsWith('IndexAlreadyExistsException')) {
        if (throwIfExists) throw new IndexAlreadyExistsException(name, e.response);
        return e.response;
      }
      rethrow;
    }
  }

  /// Deletes an index by [name] or all indices if _all is passed.
  ///
  /// Examples:
  /// ```dart
  ///   // Deletes the movie index.
  ///   await elasticsearch.deleteIndex('movie-index');
  ///
  ///   // Deletes all the indexes. Be careful with this!
  ///   await elasticsearch.deleteIndex('_all');
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/indices-delete-index.html)
  Future deleteIndex(String name) {
    return _delete(name);
  }

  /// Searches the given [index] or all indices if _all is passed.
  ///
  /// Examples:
  /// ```dart
  ///   // Will search all indices and matches everything.
  ///   await elasticsearch.search();
  ///
  ///   // Search the movie index that matches everything.
  ///   await elasticsearch.search(index: 'movie-index');
  ///
  ///   // Search the movies index that matches the name with Fury.
  ///   await elasticsearch.search(index: 'movie-index', query: {
  ///     "query": {
  ///       "match": {"name": "Fury"}
  ///     }
  ///   });
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/search-search.html)
  Future<Map<String, dynamic>> search({String index: '_all', Map<String, dynamic> query: const {}}) {
    return _post('$index/_search', query);
  }

  /// Register specific [mapping] definition for a specific [type].
  ///
  /// Examples:
  /// ```dart
  ///   await es.putMapping(
  ///     {"test-type": {"properties": {"message": {"type": "string", "store": "yes"}}}},
  ///     index: 'movie-index', type: 'movie-type'
  ///   );
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/indices-put-mapping.html)
  Future putMapping(Map<String, dynamic> mapping, {String index: '_all', String type: ''}) {
    return _put('$index/_mapping/$type', mapping);
  }

  /// Retrieve mapping definitions for an [index] or index/type.
  /// Gets all the mappings if _all is passed.
  ///
  /// Examples:
  /// ```dart
  ///   // Get all the mappings on the specific index.
  ///   await es.getMapping(index: 'movie-index');
  ///
  ///   // Get mapping on the index and the specific type.
  ///   await es.getMapping(index: 'movie-index', type: 'movie-type');
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/indices-get-mapping.html)
  Future getMapping({String index: '_all', String type: ''}) {
    return _get('$index/_mapping/$type');
  }

  /// Perform many index, delete, create, or update operations in a single call.
  ///
  /// Examples:
  /// ```dart
  ///   await es.bulk([
  ///     {"index": {"_index": "movie-index", "_type": "movies", "_id": "1"} },
  ///     {"name": "Fury", "year": "2014" }
  ///   ]);
  ///
  ///   await es.bulk([
  ///     {"delete": {"_index": "movie-index", "_type": "movies", "_id": "2"} },
  ///   ]);
  ///
  ///   await es.bulk([
  ///     {"create": {"_index": "movie-index", "_type": "movies", "_id": "3"} },
  ///     {"name": "Fury", "year": "2014" }
  ///   ]);
  ///
  ///   await es.bulk([
  ///     {"index": {"_index": "movie-index", "_type": "movies", "_id": "1"} },
  ///     {"name": "Fury", "year": "2014" }
  ///     {"index": {"_index": "movie-index", "_type": "movies", "_id": "2"} },
  ///     {"name": "Titanic", "year": "1997" },
  ///     {"index": {"_index": "movie-index", "_type": "movies", "_id": "3"} },
  ///     {"name": "Annabelle", "year": "2014" }
  ///   ]);
  /// ```
  ///
  /// For more information see:
  ///   [Elasticsearch documentation](http://elastic.co/guide/en/elasticsearch/reference/1.5/docs-bulk.html)
  Future bulk(List<Map> mapList, {String index: '_all', String type: ''}) {
    // Elasticsearch needs maps to be on new lines. Last line needs
    // to be a newline as well.
    var body = mapList.map(JSON.encode).join('\n') + '\n';

    return _post('$index/$type/_bulk', body);
  }

  Future _get(String path) => _request('GET', path);
  Future _post(String path, body) => _request('POST', path, body);
  Future _put(String path, body) => _request('PUT', path, body);
  Future _delete(String path) => _request('DELETE', path);

  Future _request(String method, String path, [body]) async {
    var request = new http.Request(method, Uri.parse('$host/$path'));
    if (body != null) {
      if (body is! String) {
        body = JSON.encode(body);
      }
      request.body = body;
    }

    var response = await request.send();
    var responseBody = _responseDecoder.convert(await response.stream.toBytes());

    if (response.statusCode >= 400) {
      if (responseBody['error'].startsWith('IndexMissingException')) {
        throw new IndexMissingException(responseBody);
      }
      throw new ElasticSearchException(responseBody);
    }

    return responseBody;
  }
}
