import 'package:xml/xml.dart';
import '../tiled.dart';
import 'tile_map_parser.dart';
import 'tile_map.dart';
import 'tile.dart';
import 'node_dsl.dart';
import 'flips.dart';

class Layer {
  static const int FLIPPED_HORIZONTALLY_FLAG = 0x80000000;
  static const int FLIPPED_VERTICALLY_FLAG = 0x40000000;
  static const int FLIPPED_DIAGONALLY_FLAG = 0x20000000;

  String name = "";
  int width = 0;
  int height = 0;
  bool visible = true;

  Map<String?, dynamic> properties = {};

  TileMap? map;
  late List<List<int>> tileMatrix;
  late List<List<Flips>> tileFlips;

  List<List<Tile>>? _tiles;
  List<List<Tile>> get tiles {
    if (_tiles == null) {
      _recalculateTiles();
    }
    return _tiles!;
  }

  Layer(this.name, this.width, this.height) : visible = true;

  Layer.fromXML(XmlElement element) {
    NodeDSL.on(element, (dsl) {
      name = dsl.strOr('name', name);
      width = dsl.intOr('width', width);
      height = dsl.intOr('height', height);
      visible = dsl.boolOr('visible', true);
    });

    final dataElement = element.children.firstWhere(
      (node) => node is XmlElement && node.name.local == 'data',
    );
    if (dataElement is XmlElement) {
      final decoder = TileMapParser.getDecoder(
        dataElement.getAttribute('encoding')!,
      );
      final decompressor = TileMapParser.getDecompressor(
        dataElement.getAttribute('compression'),
      );

      final decodedString = decoder(dataElement.text);
      final inflatedString = decompressor?.call(decodedString) ?? decodedString;

      assembleTileMatrix(inflatedString);
    }

    properties = TileMapParser.parsePropertiesFromElement(element);
  }

  // TMX data format documented here:
  // https://github.com/bjorn/tiled/wiki/TMX-Map-Format#data
  void assembleTileMatrix(var bytes) {
    tileMatrix = List.generate(height, (_) => List<int>.filled(width, 0));
    tileFlips = List.generate(height,
        (_) => List<Flips>.filled(width, const Flips(false, false, false)));

    var tileIndex = 0;
    for (var y = 0; y < height; ++y) {
      for (var x = 0; x < width; ++x) {
        var globalTileId = bytes[tileIndex] |
            bytes[tileIndex + 1] << 8 |
            bytes[tileIndex + 2] << 16 |
            bytes[tileIndex + 3] << 24;

        tileIndex += 4;

        // Read out the flags
        final flippedHorizontally =
            (globalTileId & FLIPPED_HORIZONTALLY_FLAG) ==
                FLIPPED_HORIZONTALLY_FLAG;
        final flippedVertically =
            (globalTileId & FLIPPED_VERTICALLY_FLAG) == FLIPPED_VERTICALLY_FLAG;
        final flippedDiagonally =
            (globalTileId & FLIPPED_DIAGONALLY_FLAG) == FLIPPED_DIAGONALLY_FLAG;

        // Save rotation flags
        tileFlips[y][x] = Flips(
          flippedHorizontally,
          flippedVertically,
          flippedDiagonally,
        );

        // Clear the flags
        globalTileId &= ~(FLIPPED_HORIZONTALLY_FLAG |
            FLIPPED_VERTICALLY_FLAG |
            FLIPPED_DIAGONALLY_FLAG);

        tileMatrix[y][x] = globalTileId;
      }
    }
  }

  void _recalculateTiles() {
    int px = 0;
    int py = 0;

    _tiles = List.generate(
        height, (_) => List<Tile>.filled(width, Tile(0, Tileset(0))));
    _tiles!.asMap().forEach((j, List<Tile> rows) {
      px = 0;

      rows.asMap().forEach((i, Tile t) {
        final tileId = tileMatrix[j][i];
        final flips = tileFlips[j][i];
        final tile = map!.getTileByGID(tileId)
          ..x = i
          ..y = j
          ..px = px
          ..py = py
          ..flips = flips;

        _tiles![j][i] = tile;
        px += map!.tileWidth!;
      });

      py += map!.tileHeight!;
    });
  }
}
