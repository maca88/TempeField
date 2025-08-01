import process from 'process';
import fs from 'fs';
import path from 'path';
import { EOL } from 'os';
import { XMLParser, XMLBuilder } from 'fast-xml-parser';

class TextInfo {
  constructor(x, y, font, justification, maxWidth) {
    this.x = x;
    this.y = y;
    this.font = font;
    this.justification = justification;
    this.maxWidth = maxWidth;
  }

  equals(textInfo) {
    return textInfo != null &&
      this.x === textInfo.x &&
      this.y === textInfo.y &&
      this.font === textInfo.font &&
      this.justification === textInfo.justification &&
      this.maxWidth === textInfo.maxWidth;
  }
}

class FieldInfo {
  constructor(width, height, obscurity, label, value) {
    this.width = width;
    this.height = height;
    this.obscurity = obscurity;
    this.label = label;
    this.value = value;
  }

  matches(fieldInfo) {
    return Math.abs(this.width - fieldInfo.width) <= 2 &&
           Math.abs(this.height - fieldInfo.height) <= 2 &&
           this.obscurity === fieldInfo.obscurity;
  }

  equals(fieldInfo) {
    return this.matches(fieldInfo) &&
           (this.label === fieldInfo.label || this.label?.equals(fieldInfo.label)) &&
           this.value.equals(fieldInfo.value);
  }

  compare(fieldInfo) {
    if (this.width < fieldInfo.width) {
      return -1;
    }

    if (this.width > fieldInfo.width) {
      return 1;
    }

    if (this.height < fieldInfo.height) {
      return -1;
    }

    if (this.height > fieldInfo.height) {
      return 1;
    }

    if (this.obscurity < fieldInfo.obscurity) {
      return -1;
    }

    if (this.obscurity < fieldInfo.obscurity) {
      return 1;
    }

    return 0;
  }
}

class ProductOverride {
  constructor(data) {
    data = data || {};
    this.fields = (data.fields || []).map(o => new FieldOverride(o));
    this.simFonts = {};
    this.fontSizes = {};
    for (const [key, value] of Object.entries(data.simFonts || {})) {
      this.simFonts[key.toLowerCase()] = value.toLowerCase();
    }

    for (const [key, value] of Object.entries(data.fontSizes || {})) {
      this.fontSizes[key.toLowerCase()] = value;
    }
  }
}

class FieldOverride {
  constructor(data) {
    this.obscurity = data.obscurity;
    this.fromHeight = data.fromHeight || data.height;
    this.toHeight = data.toHeight || data.height;
    this.fromWidth = data.fromWidth || data.width;
    this.toWidth = data.toWidth || data.width;
    this.values = data.values;
  }

  matches(fieldInfo) {
    return (this.obscurity == null || fieldInfo.obscurity == this.obscurity) &&
      (this.fromHeight == null || fieldInfo.height >= this.fromHeight) &&
      (this.toHeight == null || fieldInfo.height <= this.toHeight) &&
      (this.fromWidth == null || fieldInfo.width >= this.fromWidth) &&
      (this.toWidth == null || fieldInfo.width <= this.toWidth);
  }

  apply(fieldInfo) {
    const values = this.values;
    if (values.labelFont) {
      fieldInfo.label.font = values.labelFont;
    }

    if (values.labelYOffset) {
      fieldInfo.label.y += values.labelYOffset;
    }

    if (values.valueFont) {
      fieldInfo.value.font = values.valueFont;
    }

    if (values.valueYOffset) {
      fieldInfo.value.y += values.valueYOffset;
    }
  }
}

class ResourceWriter {

  devicesFolder = path.join(process.env.CIQ_HOME2, '..', '..', 'Devices');
  fontSizeRegex = /_([\d]+)[A-Z]*$/m;
  obscurityValues = {
    'left': 1,
    'top': 2,
    'right': 4,
    'bottom': 8
  };
  justificationValues = {
    'right': 0,
    'center': 1,
    'left': 2
  };
  device = null;
  fontsInfo = null;
  layouts = null;
  overrides = null;

  constructor(device, overrides) {
    this.device = device;
    this.overrides = new ProductOverride(overrides);
    const deviceDataPath = path.join(this.devicesFolder, device, 'simulator.json');
    if (!fs.existsSync(deviceDataPath)) {
      throw new Error('Device is not installed');
    }

    const data = JSON.parse(fs.readFileSync(deviceDataPath));
    this.fontsInfo = {};
    this.layouts = data.layouts;
    let fonts = data.fonts.find(o => o.fontSet === 'ww').fonts;
    let i = 0;
    while (i < fonts.length) {
      const font = fonts[i];
      if (font.type === 'system_ttf') {
        i++;
        continue;
      }

      font.name = font.name.toLowerCase();
      if (font.name.startsWith('simextnumber') && this.overrides.simFonts[font.name]) {
        this.fontsInfo[font.name] = this.fontsInfo[this.overrides.simFonts[font.name]];
        if (!this.fontsInfo[font.name]) {
          throw new Error(`Unable to translate simulator font ${font.name}, device ${device}`);
        }

        i++;
        continue;
      }

      let fontSize;
      if (this.overrides.fontSizes[font.name]) {
        fontSize = this.overrides.fontSizes[font.name];
      } else if (font.size) {
        fontSize = Math.round(font.size);
      } else {
        let match;
        if ((match = this.fontSizeRegex.exec(font.filename)) === null) {
          throw new Error(`Unable to detect font size for font ${font.filename}, device ${device}`);
        }

        fontSize = parseInt(match[1]);
      }

      const id = font.name === 'glanceFont' ? 18
        : font.name === 'glanceNumberFont' ? 19
        : font.name.startsWith('simextnumber') ? this.getSimilarFontId(fontSize)
        : i;

      this.fontsInfo[font.name] = {
        id: id,
        size: fontSize
      };

      i++;
    }
    //console.log(this.fontsInfo);
  }

  write() {
    const metadata = [];
    for (let layout of this.layouts) {
      var dataFieldLayouts = layout.datafields.datafields;
      for (let dataFieldLayout of dataFieldLayouts) {
        var fields = dataFieldLayout.fields;
        for (let field of fields) {
          var location = field.location;
          var fieldInfo = new FieldInfo(
            location.width,
            location.height,
            this.getObscurityValue(field.obscurity),
            this.getTextInfo(field.label, location.width),
            this.getTextInfo(field.data, location.width),
          );

          const matches = metadata.filter(f => f.matches(fieldInfo));
          if (matches.length === 0) {
            metadata.push(fieldInfo);
          } else if (matches.length > 1) {
            //console.log('duplicate', fieldInfo, matches);
            continue;
            //throw new Error("Duplicate field info");
          } else {
            const match = matches[0];
            if (!match.equals(fieldInfo)) {
              if ((!match.label && fieldInfo.label)) {
                // Prefer field with label
                metadata.splice(metadata.indexOf(match), 1);
                metadata.push(fieldInfo);
              } else if (fieldInfo.height > match.height) {
                // Prefer field with higher height
                //const diff = fieldInfo.height - match.height;
                //if (diff > 1) {
                //    fieldInfo.height += diff / 2; // Consolidate height
                //}

                metadata.splice(metadata.indexOf(match), 1);
                metadata.push(fieldInfo);
                //console.log('lower', match, fieldInfo);
              } else if (fieldInfo.value.font < match.value.font) {
                // Prefer field with smaller font
                metadata.splice(metadata.indexOf(match), 1);
                metadata.push(fieldInfo);
                //console.log('lower', match, fieldInfo);
              } else {
                //console.log('diff', match, fieldInfo);
              }
            }
          }
        }
      }
    }

    for (let fieldOverride of this.overrides.fields) {
      for (let item of metadata) {
        if (fieldOverride.matches(item)) {
          fieldOverride.apply(item)
        }
      }
    }

    this.writeDataXml(metadata);
    this.writeConstants(metadata);
    this.writeJungleFile();

    //console.log(metadata.sort((a, b) => a.compare(b)));
    //console.log(metadata.length);
  }

  writeDataXml(metadata) {
    const layouts =  [];
    const jsonData = [];
    for (let i = 0; i < metadata.length; i++) {
      const item = metadata[i];
      const label = item.label;
      const value = item.value;
      layouts.push(item.width);
      layouts.push(item.height);
      layouts.push(item.obscurity);
      jsonData.push(
        {
          '@id': `Layout${i}`,
          '#text': JSON.stringify([
            label?.x,
            label?.y,
            label?.font,
            label?.justification,
            label?.maxWidth,
            value.x,
            value.y,
            value.font,
            value.justification,
            value.maxWidth,
          ])
        },
      );
    }

    jsonData.unshift(
      {
        '@id': 'Layouts',
        '#text': JSON.stringify(layouts)
      },
    )

    const xmlBuilderConfig = {
      ignoreAttributes: false,
      allowBooleanAttributes: true,
      attributeNamePrefix: '@',
      reserveOrder: true,
      format: true
    };

    const builder = new XMLBuilder(xmlBuilderConfig);
    let resourceXml = builder.build({
      resources: {
        jsonData: jsonData
      }
    });

    const outputPath = `resources-${this.device}/layouts.xml`;
    const outputDir = path.dirname(outputPath);

    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    fs.writeFileSync(outputPath, resourceXml);
  }

  writeConstants(metadata) {
    let code = "const layoutResources = [";
    code += metadata.map((v, i) => `:Layout${i}`).join(',');
    code += "];";

    const outputPath = `source-${this.device}/constants.mc`;
    const outputDir = path.dirname(outputPath);

    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    fs.writeFileSync(outputPath, code);
  }

  writeJungleFile() {
    const filePath = 'monkey.jungle';
    const content = fs.readFileSync(filePath).toString();
    const match = new RegExp(`${this.device}.sourcePath.*$`, 'im').exec(content);
    if ( match) {
        return;
    }

    fs.appendFileSync(filePath, `${EOL}${this.device}.sourcePath = $(base.sourcePath);source-${this.device}`);
  }

  getObscurityValue(array) {
    let value = 0;
    for (let name of array) {
      value |= this.obscurityValues[name];
    }

    return value;
  }

  getTextInfo(data, fieldWidth) {
    if (!data) {
      return null; // Label disabled
    }

    const font = this.fontsInfo[data.font.toLowerCase()];
    if (!font) {
      throw Error(`Missing font ${data.font} for device ${this.device}. Fonts: ${JSON.stringify(this.fontsInfo)}`);
    }

    return new TextInfo(
      data.x,
      data.y,
      font.id,
      this.justificationValues[data.justification],
      data.width ? Math.min(fieldWidth, data.width) : null
    );
  }

  getSimilarFontId(fontSize) {
    let lastFontInfo = null;
    for (let fontName in this.fontsInfo) {
      const fontInfo = this.fontsInfo[fontName];
      if (fontInfo.size === fontSize) {
        return fontInfo.id
      } else if (fontInfo.size > fontSize) {
        return lastFontInfo?.id || 0;
      }

      lastFontInfo = fontInfo;
    }

    return 8;
  }
}

const manifestPath = 'manifest.xml';
if (!fs.existsSync(manifestPath)) {
  throw new Error('manifest.xml does not exist');
}

const manifestXml = fs.readFileSync(manifestPath);
const xmlParserConfig = {
  ignoreAttributes: false,
  allowBooleanAttributes: true,
  attributeNamePrefix: '@',
  reserveOrder: true
}
const parser = new XMLParser(xmlParserConfig);
const xmlData = parser.parse(manifestXml);

// Load overrides
const overridesPath = 'overrides.json';
const overrides = fs.existsSync(overridesPath)
  ? JSON.parse(fs.readFileSync(overridesPath))
  : {};

//var resourceWriter = new ResourceWriter('fenix7');
//resourceWriter.write();

for (let product of xmlData['iq:manifest']['iq:application']['iq:products']['iq:product']) {
  var productId = product['@id'];
  var productOverrides = overrides[productId];
  while ((typeof productOverrides === 'string' || productOverrides instanceof String)) {
    productOverrides = overrides[productOverrides];
  }

  var resourceWriter = new ResourceWriter(productId, productOverrides);
  resourceWriter.write();
}

