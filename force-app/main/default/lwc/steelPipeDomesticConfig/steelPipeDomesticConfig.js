import { LightningElement, track, api } from 'lwc';
import getRateCardJson from '@salesforce/apex/CreateQuoteController.getRateCardJson';
import getPricingRates from '@salesforce/apex/CreateQuoteController.getPricingRates';

const STEEL_TYPE_OPTIONS = [
    { label: "Black Steel", value: "Black Steel" },
    { label: "Galvanized Iron (GI)", value: "Galvanized Iron (GI)" }
];

const DESIGNATION_OPTIONS = [
    { label: "MS ERW", value: "MS ERW" },
    { label: "GI ERW", value: "GI ERW" },
    { label: "CS ERW", value: "CS ERW" }
];

const STANDARD_OPTIONS = [
    { label: "IS 1239", value: "IS 1239" },
    { label: "IS 1161", value: "IS 1161" },
    { label: "IS 3589", value: "IS 3589" },
    { label: "IS 4270", value: "IS 4270" },
    { label: "IS 4923", value: "IS 4923" },
    { label: "IS 9295", value: "IS 9295" },
    { label: "IS 10577", value: "IS 10577" },
    { label: "ASTM A 53 Grade A", value: "ASTM A 53 Grade A" },
    { label: "ASTM A 53 Grade B", value: "ASTM A 53 Grade B" },
    { label: "IS 3601", value: "IS 3601" }
];

const STANDARD_DIMENSIONS_MAP = {
    "IS 1239": {
        "15": "21.8", "20": "27.3", "25": "34.2", "32": "42.9",
        "40": "48.8", "50": "60.8", "65": "76.6", "80": "89.5",
        "100": "115.0", "125": "140.8", "150": "166.5"
    },
    "IS 3589": {
        "150": "168.3", "200": "219.1", "250": "273.0",
        "300": "323.9", "350": "355.6", "400": "406.4"
    },
    "IS 1161": {
        "15": "21.3", "20": "26.9", "25": "33.7", "32": "42.4",
        "40": "48.3", "50": "60.3", "65": "76.1", "80": "88.9",
        "90": "101.6", "100": "114.3", "110": "127.0", "125": "139.7",
        "135": "152.4", "150": "168.3", "175": "193.7", "200": "219.1",
        "250": "273.0", "300": "323.9", "350": "355.6"
    },
    "IS 4270": {
        "100": "114.3", "125": "141.3", "150": "168.3", "175": "193.7",
         "200": "219.1", "225": "244.5", "250": "273.1", "300": "323.9",
        "350": "355.6", "400": "406.4"
    },
    "IS 10577": {
        "15": "21.8", "20": "27.3", "25": "34.2"
    },
    "ASTMA": {
        "15": "21.3", "20": "26.7", "25": "33.4", "32": "42.2", "40": "48.3", "50": "60.3",
        "65": "73.0", "80": "88.9", "90": "101.6", "100": "114.3", "110": "127", "125": "141.3",
        "135": "152.4", "150": "168.3", "175": "193.7", "200": "219.1", "225": "244.5",
        "250": "273.0", "300": "323.9", "350": "355.6", "400": "406.4"
    },
    "ASTMA-B": {
        "15": "21.3", "20": "26.7", "25": "33.4", "32": "42.2", "40": "48.3", "50": "60.3",
        "65": "73.0", "80": "88.9", "90": "101.6", "100": "114.3", "110": "127", "125": "141.3",
        "135": "152.4", "150": "168.3", "175": "193.7", "200": "200.0", "225": "244.5",
        "250": "250.0", "300": "300.0", "350": "355.6", "355.6": "355.6", "400": "406.4", "406.4": "406.4"
    },
    "IS 4270": {
        "100": "114.3",
        "125": "141.3",
        "150": "168.3",
        "175": "193.7",
        "200": "219.1",
        "225": "244.5",
        "250": "273.0",
        "300": "323.9"
    }
};

const END_FINISH_OPTIONS = [
    { label: "Plain End", value: "Plain End" },
    { label: "Beveled End", value: "Beveled End" },
    { label: "Threaded and Socketed", value: "Threaded and Socketed" },
    { label: "Threaded", value: "Threaded" }
];

const UOM_OPTIONS = [
    { label: "MT", value: "MT" },
    { label: "Meters", value: "Meters" },
    { label: "Pieces", value: "Pieces" }
];

// HARDCODED FALLBACK: This guarantees the UI never breaks even if the database JSON fails to load or parse.
const FALLBACK_DOMESTIC_CONFIG = {"WEIGHT_MAP":{"IS 1239|Light|2|15mm":0.947,"IS 1239|Light|2.3|20mm":1.38,"IS 1239|Light|2.6|25mm":1.98,"IS 1239|Light|2.6|32mm":2.54,"IS 1239|Light|2.9|40mm":3.23,"IS 1239|Light|2.9|50mm":4.08,"IS 1239|Light|3.2|65mm":5.71,"IS 1239|Light|3.2|80mm":6.72,"IS 1239|Light|3.6|100mm":9.75,"IS 1239|Medium|2.6|15mm":1.21,"IS 1239|Medium|2.6|20mm":1.56,"IS 1239|Medium|3.2|25mm":2.41,"IS 1239|Medium|3.2|32mm":3.1,"IS 1239|Medium|3.2|40mm":3.56,"IS 1239|Medium|3.6|50mm":5.03,"IS 1239|Medium|3.6|65mm":6.42,"IS 1239|Medium|4|80mm":8.36,"IS 1239|Medium|4.5|100mm":12.2,"IS 1239|Heavy|3.2|15mm":1.44,"IS 1239|Heavy|3.2|20mm":1.87,"IS 1239|Heavy|4|25mm":2.93,"IS 1239|Heavy|4|32mm":3.79,"IS 1239|Heavy|4|40mm":4.37,"IS 1239|Heavy|4.5|50mm":6.19,"IS 1239|Heavy|4.5|65mm":7.93,"IS 1239|Heavy|4.8|80mm":9.9,"IS 1239|Heavy|5.4|100mm":14.5,"IS 1161|Default|2|15mm":0.95,"IS 1161|Default|2.5|15mm":1.16,"IS 1161|Default|3|15mm":1.35,"IS 1161|Default|2|20mm":1.23,"IS 1161|Default|2.5|20mm":1.5,"IS 1161|Default|3|20mm":1.77,"IS 1161|Default|2|25mm":1.56,"IS 1161|Default|2.5|25mm":1.92,"IS 1161|Default|3|25mm":2.27,"IS 1161|Default|2|32mm":1.99,"IS 1161|Default|2.5|32mm":2.46,"IS 1161|Default|3|32mm":2.91,"IS 1161|Default|4|32mm":3.79,"IS 1161|Default|2|40mm":2.28,"IS 1161|Default|2.5|40mm":2.82,"IS 1161|Default|3|40mm":3.35,"IS 1161|Default|4|40mm":4.37,"IS 1161|Default|2|50mm":2.88,"IS 1161|Default|2.5|50mm":3.56,"IS 1161|Default|3|50mm":4.24,"IS 1161|Default|4|50mm":5.55,"IS 1161|Default|2|65mm":3.65,"IS 1161|Default|2.5|65mm":4.54,"IS 1161|Default|3|65mm":5.41,"IS 1161|Default|4|65mm":7.11,"IS 1161|Default|5|65mm":8.77,"IS 1161|Default|2|80mm":4.29,"IS 1161|Default|2.5|80mm":5.33,"IS 1161|Default|3|80mm":6.36,"IS 1161|Default|4|80mm":8.38,"IS 1161|Default|5|80mm":10.35,"IS 1161|Default|2|90mm":4.91,"IS 1161|Default|2.5|90mm":6.11,"IS 1161|Default|3|90mm":7.29,"IS 1161|Default|4|90mm":9.63,"IS 1161|Default|5|90mm":11.91,"IS 1161|Default|2.5|100mm":6.89,"IS 1161|Default|3|100mm":8.23,"IS 1161|Default|4|100mm":10.88,"IS 1161|Default|5|100mm":13.48,"IS 1161|Default|6|100mm":16.03,"IS 1161|Default|6.3|100mm":16.78,"IS 1161|Default|2.9|110mm":8.88,"IS 1161|Default|3.2|110mm":9.77,"IS 1161|Default|3.6|110mm":10.96,"IS 1161|Default|4|110mm":12.13,"IS 1161|Default|5|110mm":15.04,"IS 1161|Default|3|125mm":10.11,"IS 1161|Default|4|125mm":13.39,"IS 1161|Default|5|125mm":16.61,"IS 1161|Default|6|125mm":19.78,"IS 1161|Default|6.3|125mm":20.73,"IS 1161|Default|3|135mm":11.05,"IS 1161|Default|4|135mm":14.64,"IS 1161|Default|5|135mm":18.18,"IS 1161|Default|6|135mm":21.66,"IS 1161|Default|6.3|135mm":22.7,"IS 1161|Default|3|150mm":11.99,"IS 1161|Default|4|150mm":15.89,"IS 1161|Default|5|150mm":19.74,"IS 1161|Default|6|150mm":23.54,"IS 1161|Default|6.3|150mm":24.67,"IS 1161|Default|4|175mm":18.71,"IS 1161|Default|5|175mm":23.27,"IS 1161|Default|6|175mm":27.77,"IS 1161|Default|6.3|175mm":29.12,"IS 1161|Default|4|200mm":21.22,"IS 1161|Default|5|200mm":26.4,"IS 1161|Default|6|200mm":31.53,"IS 1161|Default|6.3|200mm":33.06,"IS 1161|Default|8|200mm":41.65,"IS 1161|Default|5|250mm":33.05,"IS 1161|Default|6|250mm":39.51,"IS 1161|Default|6.3|250mm":41.44,"IS 1161|Default|8|250mm":52.28,"IS 1161|Default|6|300mm":47.04,"IS 1161|Default|6.3|300mm":49.34,"IS 1161|Default|8|300mm":62.32,"IS 1161|Default|5|350mm":43.23,"IS 1161|Default|6|350mm":51.73,"IS 1161|Default|6.3|350mm":54.27,"IS 1161|Default|8|350mm":68.58,"IS 3589|Default|4|150mm":16.207,"IS 3589|Default|4.5|150mm":18.177,"IS 3589|Default|4.85|150mm":18.549,"IS 3589|Default|5|150mm":20.135,"IS 3589|Default|5.4|150mm":21.692,"IS 3589|Default|5.5|150mm":22.081,"IS 3589|Default|6|150mm":24.014,"IS 3589|Default|6.35|150mm":25.36,"IS 3589|Default|7|150mm":27.844,"IS 3589|Default|4|200mm":21.217,"IS 3589|Default|4.5|200mm":23.814,"IS 3589|Default|4.85|200mm":25.625,"IS 3589|Default|5|200mm":26.399,"IS 3589|Default|5.4|200mm":28.457,"IS 3589|Default|5.5|200mm":28.971,"IS 3589|Default|6|200mm":31.53,"IS 3589|Default|6.35|200mm":33.315,"IS 3589|Default|7|200mm":36.613,"IS 3589|Default|7.5|200mm":39.135,"IS 3589|Default|8|200mm":41.646,"IS 3589|Default|9|200mm":46.63,"IS 3589|Default|9.5|200mm":49.103,"IS 3589|Default|10|200mm":51.564,"IS 3589|Default|10.5|200mm":54.013,"IS 3589|Default|4|250mm":26.534,"IS 3589|Default|4.5|250mm":29.795,"IS 3589|Default|4.85|250mm":32.071,"IS 3589|Default|5|250mm":33.044,"IS 3589|Default|5.4|250mm":35.635,"IS 3589|Default|5.5|250mm":36.281,"IS 3589|Default|6|250mm":39.505,"IS 3589|Default|6.35|250mm":41.755,"IS 3589|Default|7|250mm":45.917,"IS 3589|Default|7.5|250mm":49.104,"IS 3589|Default|8|250mm":52.279,"IS 3589|Default|9|250mm":58.592,"IS 3589|Default|9.5|250mm":61.73,"IS 3589|Default|10|250mm":64.856,"IS 3589|Default|10.5|250mm":67.969,"IS 3589|Default|4|300mm":31.555,"IS 3589|Default|4.5|300mm":35.444,"IS 3589|Default|4.85|300mm":38.159,"IS 3589|Default|5|300mm":39.32,"IS 3589|Default|5.4|300mm":42.413,"IS 3589|Default|5.5|300mm":43.185,"IS 3589|Default|6|300mm":47.036,"IS 3589|Default|6.35|300mm":49.725,"IS 3589|Default|7|300mm":54.703,"IS 3589|Default|7.5|300mm":58.518,"IS 3589|Default|8|300mm":62.321,"IS 3589|Default|9|300mm":69.889,"IS 3589|Default|9.5|300mm":73.654,"IS 3589|Default|10|300mm":77.408,"IS 3589|Default|10.5|300mm":81.149,"IS 3589|Default|4|350mm":34.682,"IS 3589|Default|4.5|350mm":38.962,"IS 3589|Default|4.85|350mm":41.95,"IS 3589|Default|5|350mm":43.229,"IS 3589|Default|5.4|350mm":46.634,"IS 3589|Default|5.5|350mm":47.484,"IS 3589|Default|6|350mm":51.727,"IS 3589|Default|6.35|350mm":54.689,"IS 3589|Default|7|350mm":60.175,"IS 3589|Default|7.5|350mm":64.381,"IS 3589|Default|8|350mm":68.575,"IS 3589|Default|9|350mm":76.924,"IS 3589|Default|9.5|350mm":81.081,"IS 3589|Default|10|350mm":85.225,"IS 3589|Default|10.5|350mm":89.357,"IS 3589|Default|4|400mm":39.702,"IS 3589|Default|4.5|400mm":44.654,"IS 3589|Default|4.85|400mm":48.086,"IS 3589|Default|5|400mm":49.554,"IS 3589|Default|5.4|400mm":53.465,"IS 3589|Default|5.5|400mm":54.442,"IS 3589|Default|6|400mm":59.317,"IS 3589|Default|6.35|400mm":62.723,"IS 3589|Default|7|400mm":69.031,"IS 3589|Default|7.5|400mm":73.869,"IS 3589|Default|8|400mm":78.695,"IS 3589|Default|9|400mm":88.31,"IS 3589|Default|9.5|400mm":93.099,"IS 3589|Default|10|400mm":97.876,"IS 3589|Default|10.5|400mm":102.64,"IS 4270|Screwed-End-Socket|5|100mm":13.46,"IS 4270|Screwed-End-Socket|5.4|100mm":14.5,"IS 4270|Screwed-End-Socket|6|100mm":16.02,"IS 4270|Screwed-End-Socket|5|125mm":16.8,"IS 4270|Screwed-End-Socket|5.4|125mm":18.1,"IS 4270|Screwed-End-Socket|6|125mm":20.01,"IS 4270|Screwed-End-Socket|6.4|125mm":21.29,"IS 4270|Screwed-End-Socket|7.1|125mm":23.5,"IS 4270|Screwed-End-Socket|5|150mm":20.13,"IS 4270|Screwed-End-Socket|5.4|150mm":21.6,"IS 4270|Screwed-End-Socket|6|150mm":24.01,"IS 4270|Screwed-End-Socket|6.4|150mm":25.55,"IS 4270|Screwed-End-Socket|7.1|150mm":28.2,"IS 4270|Screwed-End-Socket|5.4|175mm":25.1,"IS 4270|Screwed-End-Socket|6|175mm":27.77,"IS 4270|Screwed-End-Socket|6.4|175mm":29.6,"IS 4270|Screwed-End-Socket|7.1|175mm":32.67,"IS 4270|Screwed-End-Socket|8|175mm":36.6,"IS 4270|Screwed-End-Socket|5.4|200mm":28.46,"IS 4270|Screwed-End-Socket|6|200mm":31.53,"IS 4270|Screwed-End-Socket|6.4|200mm":33.6,"IS 4270|Screwed-End-Socket|7.1|200mm":37.12,"IS 4270|Screwed-End-Socket|8|200mm":41.6,"IS 4270|Screwed-End-Socket|6|225mm":35.29,"IS 4270|Screwed-End-Socket|7.1|225mm":41.6,"IS 4270|Screwed-End-Socket|7.1|250mm":46.57,"IS 4270|Screwed-End-Socket|8|250mm":52.3,"IS 4270|Screwed-End-Socket|10|250mm":64.9,"IS 4270|Screwed-End-Socket|7.1|300mm":55.47,"IS 4270|Screwed-End-Socket|8|300mm":62.3,"IS 4270|Screwed-End-Socket|10|300mm":77.4,"IS 4270|Screwed-flush-Butt-joints|6|100mm":16.02,"IS 4270|Screwed-flush-Butt-joints|6|125mm":20.01,"IS 4270|Screwed-flush-Butt-joints|8|150mm":31.62,"IS 4270|Screwed-flush-Butt-joints|8|175mm":35.63,"IS 4270|Screwed-flush-Butt-joints|10|200mm":51.56,"IS 4270|Screwed-flush-Butt-joints|10|225mm":57.82,"IS 4270|Screwed-flush-Butt-joints|10|250mm":64.88,"IS 4270|Screwed-flush-Butt-joints|10|300mm":77.4,"IS 4270|Screwed-flush-Butt-joints|10|350mm":85.22,"IS 4270|Screwed-flush-Butt-joints|12|400mm":116.71,"IS 4270|Screwed-flush-Butt-joints|14|400mm":135.47,"IS 4923|Square|1.8|19":0.91,"IS 4923|Square|2|19":0.99,"IS 4923|Square|2.3|19":1.1,"IS 4923|Square|2.6|19":1.2,"IS 4923|Square|3|19":1.32,"IS 4923|Square|3.2|19":1.38,"IS 4923|Square|3.6|19":1.48,"IS 4923|Square|1.8|25":1.25,"IS 4923|Square|2|25":1.36,"IS 4923|Square|2.3|25":1.53,"IS 4923|Square|2.6|25":1.69,"IS 4923|Square|3|25":1.89,"IS 4923|Square|3.2|25":1.98,"IS 4923|Square|3.6|25":2.16,"IS 4923|Square|1.8|32":1.64,"IS 4923|Square|2|32":1.8,"IS 4923|Square|2.3|32":2.04,"IS 4923|Square|2.6|32":2.26,"IS 4923|Square|3|32":2.55,"IS 4923|Square|3.2|32":2.69,"IS 4923|Square|3.6|32":2.95,"IS 4923|Square|1.8|38":1.98,"IS 4923|Square|2|38":2.18,"IS 4923|Square|2.3|38":2.47,"IS 4923|Square|2.6|38":2.94,"IS 4923|Square|3|38":3.11,"IS 4923|Square|3.2|38":3.29,"IS 4923|Square|3.6|38":3.63,"IS 4923|Square|1.8|49.5":2.63,"IS 4923|Square|2|49.5":2.9,"IS 4923|Square|2.3|49.5":3.3,"IS 4923|Square|2.6|49.5":3.69,"IS 4923|Square|3|49.5":4.2,"IS 4923|Square|3.2|49.5":4.44,"IS 4923|Square|3.6|49.5":4.93,"IS 4923|Square|2|60":3.6,"IS 4923|Square|2.3|60":4.12,"IS 4923|Square|2.6|60":4.63,"IS 4923|Square|2.9|60":5.13,"IS 4923|Square|3|60":5.3,"IS 4923|Square|3.2|60":5.63,"IS 4923|Square|3.6|60":6.29,"IS 4923|Square|4|60":6.92,"IS 4923|Square|4.3|60":7.39,"IS 4923|Square|4.5|60":7.7,"IS 4923|Square|4.8|60":8.16,"IS 4923|Square|5|60":8.46,"IS 4923|Square|2.5|72":5.38,"IS 4923|Square|2.6|72":5.58,"IS 4923|Square|2.9|72":6.18,"IS 4923|Square|3|72":6.38,"IS 4923|Square|3.2|72":6.78,"IS 4923|Square|3.6|72":7.55,"IS 4923|Square|4|72":8.32,"IS 4923|Square|4.3|72":8.89,"IS 4923|Square|4.5|72":9.27,"IS 4923|Square|4.8|72":9.83,"IS 4923|Square|5|72":10.2,"IS 4923|Square|2.5|80":6.01,"IS 4923|Square|2.6|80":6.24,"IS 4923|Square|2.9|80":6.91,"IS 4923|Square|3|80":7.13,"IS 4923|Square|3.2|80":7.58,"IS 4923|Square|3.6|80":8.46,"IS 4923|Square|4|80":9.32,"IS 4923|Square|4.3|80":9.97,"IS 4923|Square|4.5|80":10.39,"IS 4923|Square|4.8|80":11.03,"IS 4923|Square|5|80":11.46,"IS 4923|Square|2.5|91.5":6.91,"IS 4923|Square|2.6|91.5":7.18,"IS 4923|Square|2.9|91.5":7.96,"IS 4923|Square|3|91.5":8.22,"IS 4923|Square|3.2|91.5":8.74,"IS 4923|Square|3.6|91.5":9.76,"IS 4923|Square|4|91.5":10.77,"IS 4923|Square|4.3|91.5":11.52,"IS 4923|Square|4.5|91.5":12.02,"IS 4923|Square|4.8|91.5":12.76,"IS 4923|Square|5|91.5":13.25,
            "IS 4923|Square|2.8|100":8.458,"IS 4923|Square|3|100":9.022,"IS 4923|Square|3.2|100":9.581,"IS 4923|Square|3.6|100":10.683,"IS 4923|Square|4|100":11.764,"IS 4923|Square|4.3|100":12.561,"IS 4923|Square|4.5|100":13.085,"IS 4923|Square|4.8|100":13.862,"IS 4923|Square|5|100":14.373,"IS 4923|Square|3|113.5":10.29,"IS 4923|Square|3.2|113.5":10.95,"IS 4923|Square|3.6|113.5":12.25,"IS 4923|Square|4|113.5":13.53,"IS 4923|Square|4.3|113.5":14.49,"IS 4923|Square|4.5|113.5":15.13,"IS 4923|Square|4.8|113.5":16.08,"IS 4923|Square|5|113.5":16.71,
            "IS 4923|Square|2|120":7.431,"IS 4923|Square|2.3|120":8.499,"IS 4923|Square|2.5|120":9.205,"IS 4923|Square|2.6|120":9.556,"IS 4923|Square|2.9|120":10.601,"IS 4923|Square|3|120":10.947,"IS 4923|Square|3.2|120":11.634,"IS 4923|Square|3.6|120":12.992,"IS 4923|Square|4|120":14.33,"IS 4923|Square|4.3|120":15.319,"IS 4923|Square|4.5|120":15.971,"IS 4923|Square|4.8|120":16.94,"IS 4923|Square|5|120":17.58,"IS 4923|Square|6|120":20.697,"IS 4923|Square|3.6|132":14.34,"IS 4923|Square|4|132":15.85,"IS 4923|Square|4.3|132":16.99,"IS 4923|Square|4.5|132":17.74,"IS 4923|Square|4.8|132":18.87,"IS 4923|Square|5|132":19.61,"IS 4923|Square|3.6|150":16.37,"IS 4923|Square|4|150":18.11,"IS 4923|Square|4.3|150":19.42,"IS 4923|Square|4.5|150":20.28,"IS 4923|Square|4.8|150":21.58,"IS 4923|Square|5|150":22.44,"IS 4923|Square|3.5|180":19.68,"IS 4923|Square|3.6|180":19.68,"IS 4923|Square|4|180":21.88,"IS 4923|Square|4.3|180":23.47,"IS 4923|Square|4.5|180":24.52,"IS 4923|Square|4.8|180":26.09,"IS 4923|Square|5|180":27.15,"IS 4923|Square|3.6|220":24.2,"IS 4923|Square|4|220":26.81,"IS 4923|Square|4.3|220":28.75,"IS 4923|Square|4.5|220":30.04,"IS 4923|Square|4.8|220":31.97,"IS 4923|Square|5|220":33.25,"IS 4923|Square|3.6|260":28.72,"IS 4923|Square|4|260":31.83,"IS 4923|Square|4.3|260":34.15,"IS 4923|Square|4.5|260":35.69,"IS 4923|Square|4.8|260":38,"IS 4923|Square|5|260":39.53,"IS 4923|Rectangular|1.8|50":1.95,"IS 4923|Rectangular|2|50":2.15,"IS 4923|Rectangular|2.3|50":2.44,"IS 4923|Rectangular|2.5|50":2.62,"IS 4923|Rectangular|2.8|50":2.89,"IS 4923|Rectangular|3|50":3.07,"IS 4923|Rectangular|3.2|50":3.24,"IS 4923|Rectangular|3.6|50":3.57,"IS 4923|Rectangular|1.8|60":2.66,"IS 4923|Rectangular|2|60":2.93,"IS 4923|Rectangular|2.3|60":3.34,"IS 4923|Rectangular|2.5|60":3.6,"IS 4923|Rectangular|2.8|60":3.99,"IS 4923|Rectangular|3|60":4.25,"IS 4923|Rectangular|3.2|60":4.5,"IS 4923|Rectangular|3.6|60":4.98,"IS 4923|Rectangular|1.8|66":2.63,"IS 4923|Rectangular|2|66":2.9,"IS 4923|Rectangular|2.3|66":3.3,"IS 4923|Rectangular|2.5|66":3.56,"IS 4923|Rectangular|2.8|66":3.95,"IS 4923|Rectangular|3|66":4.2,"IS 4923|Rectangular|3.2|66":4.44,"IS 4923|Rectangular|3.6|66":4.93,"IS 4923|Rectangular|2.5|70":3.6,"IS 4923|Rectangular|2.8|70":3.99,"IS 4923|Rectangular|3|70":4.25,"IS 4923|Rectangular|3.2|70":4.5,"IS 4923|Rectangular|3.6|70":4.98,"IS 4923|Rectangular|4|70":5.45,"IS 4923|Rectangular|4.3|70":5.8,"IS 4923|Rectangular|4.5|70":6.02,"IS 4923|Rectangular|2.5|75":3.6,"IS 4923|Rectangular|2.8|75":3.99,"IS 4923|Rectangular|3|75":4.25,"IS 4923|Rectangular|3.2|75":4.5,"IS 4923|Rectangular|3.6|75":4.98,"IS 4923|Rectangular|4|75":5.45,"IS 4923|Rectangular|4.3|75":5.8,"IS 4923|Rectangular|4.5|75":6.02,"IS 4923|Rectangular|2.5|80":4.39,"IS 4923|Rectangular|2.8|80":4.87,"IS 4923|Rectangular|3|80":5.19,"IS 4923|Rectangular|3.2|80":5.5,"IS 4923|Rectangular|3.6|80":6.11,"IS 4923|Rectangular|4|80":6.71,"IS 4923|Rectangular|4.3|80":7.15,"IS 4923|Rectangular|4.5|80":7.43,"IS 4923|Rectangular|2.5|96":5.357,"IS 4923|Rectangular|2.8|96":5.944,"IS 4923|Rectangular|3|96":6.329,
            "IS 4923|Rectangular|3.2|96":6.71,"IS 4923|Rectangular|3.6|96":7.47,"IS 4923|Rectangular|4|96":8.22,"IS 4923|Rectangular|4.3|96":8.77,"IS 4923|Rectangular|4.5|96":9.13,"IS 4923|Rectangular|2.5|100":5.598,"IS 4923|Rectangular|2.8|100":6.213,"IS 4923|Rectangular|3|100":6.617,"IS 4923|Rectangular|3.2|100":7.016,
            "IS 4923|Rectangular|3.5|100":7.61,"IS 4923|Rectangular|3.6|100":7.81,"IS 4923|Rectangular|4|100":8.59,"IS 4923|Rectangular|4.3|100":9.17,"IS 4923|Rectangular|4.5|100":9.55,"IS 4923|Rectangular|2.5|122":6.92,"IS 4923|Rectangular|2.8|122":7.695,"IS 4923|Rectangular|3|122":8.205,"IS 4923|Rectangular|3.2|122":8.709,
            "IS 4923|Rectangular|3.5|122":9.42,"IS 4923|Rectangular|3.6|122":9.67,"IS 4923|Rectangular|4|122":10.67,"IS 4923|Rectangular|4.3|122":11.4,"IS 4923|Rectangular|4.5|122":11.88,"IS 4923|Rectangular|5|122":13.07,"IS 4923|Rectangular|3.5|145":11.84,"IS 4923|Rectangular|3.6|145":12.16,"IS 4923|Rectangular|4|145":13.43,"IS 4923|Rectangular|4.3|145":14.37,"IS 4923|Rectangular|4.5|145":14.99,"IS 4923|Rectangular|5|145":16.53,
            "IS 4923|Rectangular|2|150":7.751,"IS 4923|Rectangular|2.3|150":8.868,"IS 4923|Rectangular|2.5|150":9.606,"IS 4923|Rectangular|2.8|150":10.703,"IS 4923|Rectangular|3|150":11.428,"IS 4923|Rectangular|3.2|150":12.147,"IS 4923|Rectangular|3.5|150":13.216,"IS 4923|Rectangular|3.6|150":13.57,"IS 4923|Rectangular|4|150":14.971,"IS 4923|Rectangular|4.3|150":16.008,"IS 4923|Rectangular|4.5|150":16.693,"IS 4923|Rectangular|5|150":18.381,"IS 4923|Rectangular|6|150":21.659,"IS 4923|Rectangular|2|172":8.2,"IS 4923|Rectangular|2.3|172":9.385,"IS 4923|Rectangular|2.5|172":10.167,"IS 4923|Rectangular|2.8|172":11.332,"IS 4923|Rectangular|3|172":12.101,"IS 4923|Rectangular|3.2|172":12.865,"IS 4923|Rectangular|6|172":23.006,
            "IS 4923|Rectangular|3.5|172":13.87,"IS 4923|Rectangular|3.6|172":14.25,"IS 4923|Rectangular|4|172":15.75,"IS 4923|Rectangular|4.3|172":16.87,"IS 4923|Rectangular|4.5|172":17.61,"IS 4923|Rectangular|5|172":19.43,
            "IS 4923|Rectangular|2|200":9.355,"IS 4923|Rectangular|2.3|200":10.712,"IS 4923|Rectangular|2.5|200":11.61,"IS 4923|Rectangular|2.8|200":12.948,"IS 4923|Rectangular|3|200":13.833,"IS 4923|Rectangular|3.2|200":14.712,"IS 4923|Rectangular|3.5|200":16.022,"IS 4923|Rectangular|3.6|200":16.456,"IS 4923|Rectangular|4|200":18.178,"IS 4923|Rectangular|4.3|200":19.455,"IS 4923|Rectangular|4.5|200":20.301,"IS 4923|Rectangular|5|200":22.39,"IS 4923|Rectangular|6|200":26.469,
            "IS 4923|Rectangular|2|240":11.279,"IS 4923|Rectangular|2.3|240":12.925,"IS 4923|Rectangular|2.5|240":14.016,"IS 4923|Rectangular|2.8|240":15.642,"IS 4923|Rectangular|3|240":16.719,"IS 4923|Rectangular|3.2|240":17.791,"IS 4923|Rectangular|3.5|240":19.389,"IS 4923|Rectangular|3.6|240":19.919,"IS 4923|Rectangular|4|240":22.026,"IS 4923|Rectangular|4.3|240":23.592,"IS 4923|Rectangular|4.5|240":24.63,"IS 4923|Rectangular|5|240":27.2,"IS 4923|Rectangular|6|240":32.242,"IS 9295 |Default|3.65|63.5":5.39,"IS 9295 |Default|4.5|63.5":6.55,"IS 9295 |Default|3.65|76.1":6.52,"IS 9295 |Default|4.5|76.1":7.95,"IS 9295 |Default|4.05|88.9":8.47,"IS 9295 |Default|4.85|88.9":10.05,"IS 9295 |Default|6.3|88.9":12.83,"IS 9295 |Default|4.05|101.6":9.74,"IS 9295 |Default|4.85|101.6":11.57,"IS 9295 |Default|6.3|101.6":14.81,"IS 9295 |Default|4.5|114.3":12.19,"IS 9295 |Default|4.85|114.3":14.5,"IS 9295 |Default|6.3|114.3":16.78,"IS 9295 |Default|4.5|127":13.6,"IS 9295 |Default|4.85|127":14.61,"IS 9295 |Default|5.4|127":16.49,"IS 9295 |Default|6.3|127":18.75,"IS 9295 |Default|4.5|139.7":15,"IS 9295 |Default|4.85|139.7":16.13,"IS 9295 |Default|5.4|139.7":17.89,"IS 9295 |Default|6.3|139.7":20.73,"IS 9295 |Default|4.5|152.4":16.4,"IS 9295 |Default|4.85|152.4":17.65,"IS 9295 |Default|5.4|152.4":19.58,"IS 9295 |Default|6.3|152.4":22.7,"IS 9295 |Default|4.5|159":17.1,"IS 9295 |Default|4.85|159":18.44,"IS 9295 |Default|5.4|159":20.4,"IS 9295 |Default|6.3|159":23.72,"IS 9295 |Default|4.5|165.1":17.8,"IS 9295 |Default|4.85|165.1":19.17,"IS 9295 |Default|5.4|165.1":21.27,"IS 9295 |Default|6.3|165.1":24.67,"IS 9295 |Default|4.5|168.3":18.2,"IS 9295 |Default|4.85|168.3":19.55,"IS 9295 |Default|5.4|168.3":21.69,"IS 9295 |Default|6.3|168.3":25.17,"IS 9295 |Default|5.4|193.7":25.1,"IS 9295 |Default|6.3|193.7":29.12,"IS 9295 |Default|7.1|193.7":32.67,"IS 9295 |Default|5.4|219.1":28.5,"IS 9295 |Default|6.3|219.1":33.06,"IS 9295 |Default|7.1|219.1":37.12,"IS 10577|Light|2|15mm":0.952,"IS 10577|Light|2.35|20mm":1.41,"IS 10577|Light|2.65|25mm":2.01,"IS 10577|Medium|2.65|15mm":1.22,"IS 10577|Medium|2.65|20mm":1.58,"IS 10577|Medium|3.25|25mm":2.44,"IS 10577|Heavy|3.25|15mm":1.45,"IS 10577|Heavy|3.25|20mm":1.9,"IS 10577|Heavy|4.05|25mm":2.97,"ASTMA|Default|2.77|15mm":1.27,"ASTMA|Default|2.87|20mm":1.69,"ASTMA|Default|3.38|25mm":2.5,"ASTMA|Default|3.56|32mm":3.39,"ASTMA|Default|3.68|40mm":4.05,"ASTMA|Default|3.91|50mm":5.44,"ASTMA|Default|5.16|65mm":8.63,"ASTMA|Default|5.49|80mm":11.29,"ASTMA|Default|5.74|90mm":13.57,"ASTMA|Default|6.02|100mm":16.07,"ASTMA|Default|6.55|125mm":21.77,"ASTMA|Default|7.11|150mm":28.26,"ASTMA|Default|6.35|200mm":33.31,"ASTMA|Default|7.04|200mm":36.81,"ASTMA|Default|8.18|200mm":42.55,"ASTMA|Default|10.31|200mm":54.06,
            "ASTMA-B|Default|3.76|200mm":18.2,"ASTMA-B|Default|4.19|250mm":25.4,"ASTMA-B|Default|4.57|300mm":33.3,"ASTMA-B|Default|10.31|300mm":73.66,"ASTMA-B|Default|6.35|355.6mm":54.69,"ASTMA-B|Default|7.92|355.6mm":67.91,"ASTMA-B|Default|9.52|355.6mm":81.25,"ASTMA-B|Default|6.35|406.4mm":62.65,"ASTMA-B|Default|7.92|406.4mm":77.83,"ASTMA-B|Default|9.52|406.4mm":93.18,"ASTMA|Default|6.35|250mm":41.75,"ASTMA|Default|7.8|250mm":51.01,"ASTMA|Default|9.27|250mm":60.29,"ASTMA|Default|6.35|300mm":49.73,"ASTMA|Default|8.38|300mm":65.2,"ASTMA|Default|6.35|350mm":54.69,"ASTMA|Default|7.92|350mm":67.9,"ASTMA|Default|9.52|350mm":81.25,"ASTMA|Default|6.35|400mm":62.72,"ASTMA|Default|7.92|400mm":77.92,"ASTMA|Default|9.52|400mm":93.29},"SHAPE_DEPENDENT_MAP":{"IS 1239":["Light","Medium","Heavy"],"IS 4923":["Square","Rectangular"],"IS 10577":["Light","Medium","Heavy"],"IS 4270":["Screwed-End-Socket","Screwed-flush-Butt-joints"],"ASTMA":["Default"],"ASTMA-B":["Default"]},"CLASS_DEPENDENT_MAP":{"IS 1239|Light":["2","2.3","2.6","2.9","3.2","3.6"],"IS 1239|Medium":["2.6","3.2","3.6","4","4.5","4.8"],"IS 1239|Heavy":["3.2","4","4.5","4.8","5.4"],"IS 1161|Default":["2","2.5","2.9","3","3.2","3.6","4","5","6","6.3","8"],"IS 3589|Default":["4","4.5","4.85","5","5.4","5.5","6","6.35","7","7.5","8","9","9.5","10","10.5"],"IS 4270|Screwed-End-Socket":["5.4","6.4","7.1","8","10"],"IS 4270|Screwed-flush-Butt-joints":["6","8","10","12","14"],"IS 4923|Square":["1.8","2","2.3","2.5","2.6","2.8","2.9","3","3.2","3.6","4","4.3","4.5","4.8","5","6"],"IS 4923|Rectangular":["1.8","2","2.3","2.5","2.8","3","3.2","3.5","3.6","4","4.3","4.5","5","6"],"IS 9295|Default":["3.65","4.05","4.5","4.85","5.4","6.3","7.1"],"IS 10577|Light":["2","2.35","2.65"],"IS 10577|Medium":["2.65","3.25"],"IS 10577|Heavy":["3.25","4.05"],"ASTMA|Default":["2.77","2.87","3.38","3.56","3.68","3.91","5.16","5.49","5.74","6.02","6.35","6.55","7.04","7.11","7.8","7.92","8.18","8.38","9.27","9.52","10.31"],"ASTMA-B|Default":["3.76","4.19","4.57","6.35","7.92","9.52","10.31"]},"BASE_RATES":{"Black Steel":62.5,"Galvanized Iron (GI)":70,"Stainless Steel":150}};

export default class SteelPipeDomesticConfig extends LightningElement {
    get gstColumnHeader() {
        let gst = (this.dynamicGst !== undefined && this.dynamicGst !== null) ? this.dynamicGst : 18;
        return `GST @${gst}%`;
    }
    @track pipeCount = 1;
    @track pipes = [];
    @track showCalculations = true;
    @track dynamicBaseRates = {};
    @track dynamicGst = 18;
    WEIGHT_MAP = {};
    SHAPE_DEPENDENT_MAP = {};
    CLASS_DEPENDENT_MAP = {};

    @api savedPipes = [];
    @api isReadOnly = false;
    @api showRateInDoc = false;

    async connectedCallback() {
        await Promise.all([
            this.fetchConfigData(),
            this.fetchMetadataRates()
        ]);
        
        this.initializePipes();
    }

    transformIS4270() {
        if (!this.SHAPE_DEPENDENT_MAP || !this.CLASS_DEPENDENT_MAP || !this.WEIGHT_MAP) return;
        
        const std = 'IS 4270';
        this.SHAPE_DEPENDENT_MAP[std] = ['Default'];
        
        let classSet = new Set();
        let classDependentKey1 = `${std}|Screwed-End-Socket`;
        let classDependentKey2 = `${std}|Screwed-flush-Butt-joints`;
        
        if (this.CLASS_DEPENDENT_MAP[classDependentKey1]) {
            this.CLASS_DEPENDENT_MAP[classDependentKey1].forEach(c => classSet.add(c));
            delete this.CLASS_DEPENDENT_MAP[classDependentKey1];
        }
        if (this.CLASS_DEPENDENT_MAP[classDependentKey2]) {
            this.CLASS_DEPENDENT_MAP[classDependentKey2].forEach(c => classSet.add(c));
            delete this.CLASS_DEPENDENT_MAP[classDependentKey2];
        }
        this.CLASS_DEPENDENT_MAP[`${std}|Default`] = Array.from(classSet);
        
        let newWeightMap = {};
        Object.keys(this.WEIGHT_MAP).forEach(k => {
            if (k.startsWith(`${std}|`)) {
                let parts = k.split('|');
                // parts[0] = std, parts[1] = shape, parts[2] = WT, parts[3] = NB
                let newK = `${std}|Default|${parts[2]}|${parts[3]}`;
                newWeightMap[newK] = this.WEIGHT_MAP[k];
                delete this.WEIGHT_MAP[k];
            }
        });
        Object.assign(this.WEIGHT_MAP, newWeightMap);
    }

    fetchMetadataRates() {
        return getPricingRates({ departmentName: 'Steel Pipe Domestic Config' })
            .then(result => {
                if (result && result.GST__c != null) {
                    this.dynamicGst = parseFloat(result.GST__c);
                }
            })
            .catch(error => {
                console.error('Error fetching Metadata Rates', error);
            });
    }

    fetchConfigData() {
        // Auto-Sanitizer: Cleans up trailing spaces or leftover year suffixes from the database JSON
        const cleanMapKeys = (map) => {
            let cleaned = {};
            if(map) {
                Object.keys(map).forEach(k => {
                    // Removes year suffixes (e.g., " : 1983" or ":2001")
                    let newKey = k.replace(/\s*:\s*\d{4}/g, '');
                    // Splits by the pipe, trims extra spaces around it, and rejoins (fixes "IS 9295 |Default")
                    newKey = newKey.split('|').map(p => p.trim()).join('|');
                    cleaned[newKey] = map[k];
                });
            }
            return cleaned;
        };

        return getRateCardJson({ departmentName: 'Steel Pipe Domestic Config' })
            .then(data => {
                let config;
                try {
                    // Try to parse the database result
                    if (data) {
                        let cleanData = typeof data === 'string' ? data.replace(/&quot;/g, '"').replace(/&#39;/g, "'") : data;
                        config = typeof cleanData === 'string' ? JSON.parse(cleanData) : cleanData;
                    } else {
                        throw new Error('Data is empty');
                    }
                } catch (e) {
                    console.error('Error parsing JSON Config, using permanent fallback data', e);
                    console.error('Raw Data was:', data);
                    config = FALLBACK_DOMESTIC_CONFIG;
                }

                // Populate the Maps using the Auto-Sanitizer
                this.WEIGHT_MAP = cleanMapKeys(config.WEIGHT_MAP || FALLBACK_DOMESTIC_CONFIG.WEIGHT_MAP);
                this.SHAPE_DEPENDENT_MAP = cleanMapKeys(config.SHAPE_DEPENDENT_MAP || FALLBACK_DOMESTIC_CONFIG.SHAPE_DEPENDENT_MAP);
                this.CLASS_DEPENDENT_MAP = cleanMapKeys(config.CLASS_DEPENDENT_MAP || FALLBACK_DOMESTIC_CONFIG.CLASS_DEPENDENT_MAP);
                this.dynamicBaseRates = config.BASE_RATES || FALLBACK_DOMESTIC_CONFIG.BASE_RATES;
                
                this.transformIS4270();

                // Re-eval options for existing pipes if needed
                if(this.pipes.length > 0) {
                    this.pipes = this.pipes.map(p => {
                        p.shapeOptions = this.getShapeOptions(p.standardSpecGrade);
                        if (p.shapeOptions.length === 1) {
                            p.shapeType = p.shapeOptions[0].value;
                            p.isShapeDisabled = true;
                        } else {
                            p.isShapeDisabled = false;
                        }
                        
                        p.sizeOptions = this.getSizeOptions(p.standardSpecGrade, p.shapeType);
                        p.classOptions = this.getClassOptions(p.standardSpecGrade, p.shapeType, p.sizeNb);
                        
                        if (p.classOptions.length === 1) {
                            if (!p.pipeClass && p.classOptions[0].value !== 'Default') {
                                p.pipeClass = p.classOptions[0].value;
                            }
                            p.isClassDisabled = true;
                        } else {
                            p.isClassDisabled = false;
                        }
                        this.calculatePipe(p);
                        return p;
                    });
                }
            })
            .catch(error => {
                console.error('Error fetching Rate Card Config, reverting to fallback', error);
                
                // Last line of defense fallback also utilizes the sanitizer
                this.WEIGHT_MAP = cleanMapKeys(FALLBACK_DOMESTIC_CONFIG.WEIGHT_MAP);
                this.SHAPE_DEPENDENT_MAP = cleanMapKeys(FALLBACK_DOMESTIC_CONFIG.SHAPE_DEPENDENT_MAP);
                this.CLASS_DEPENDENT_MAP = cleanMapKeys(FALLBACK_DOMESTIC_CONFIG.CLASS_DEPENDENT_MAP);
                this.dynamicBaseRates = FALLBACK_DOMESTIC_CONFIG.BASE_RATES;
                
                this.transformIS4270();
            });
    }

    initializePipes() {
        if (this.savedPipes && this.savedPipes.length > 0) {
            this.pipeCount = this.savedPipes.length;
            this.pipes = this.savedPipes.map((savedPipe, index) => {
                let pipe = this.createEmptyPipe(index);
                pipe.steelType = savedPipe.steel_type || 'Black Steel';
                pipe.designation = savedPipe.pipe_designation || 'MS ERW';
                pipe.standardSpecGrade = savedPipe.standard_spec_grade || savedPipe.standard || 'IS 1239';
                pipe.shapeType = savedPipe.shape;
                pipe.pipeClass = savedPipe.pipe_class;
                pipe.sizeNb = savedPipe.raw_size_nb || savedPipe.size_nb;
                pipe.endFinish = savedPipe.end_finish || 'Plain End';
                pipe.pipeLength = (savedPipe.pipe_length && savedPipe.pipe_length !== 'NA') ? savedPipe.pipe_length : '';
                pipe.quantity = savedPipe.quantity || 1;
                pipe.uom = savedPipe.uom || 'Pieces';
                pipe.discount = savedPipe.discount || 0;
                pipe.specialDescription = savedPipe.special_description || savedPipe.specialDescription || '';
                
                pipe.designationOptions = this.getDesignationOptions(pipe.steelType);
                pipe.shapeOptions = this.getShapeOptions(pipe.standardSpecGrade);
                if (pipe.shapeOptions.length === 1) {
                    pipe.isShapeDisabled = true;
                    pipe.shapeType = pipe.shapeOptions[0].value;
                } else {
                    pipe.isShapeDisabled = false;
                }
                pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, pipe.shapeType);
                pipe.classOptions = this.getClassOptions(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
                
                if (pipe.classOptions.length === 1) {
                    if (!pipe.pipeClass && pipe.classOptions[0].value !== 'Default') {
                        pipe.pipeClass = pipe.classOptions[0].value;
                    }
                    pipe.isClassDisabled = true;
                } else {
                    pipe.isClassDisabled = false;
                }
                
                pipe.singlePipeWeight = savedPipe.unitWeight || savedPipe.singlePipeWeight || 0;
                pipe.totalWeight = savedPipe.weight || savedPipe.totalWeight || 0;
                pipe.rateRsMtr = savedPipe.rate || savedPipe.rateRsMtr || 0;
                pipe.costPrice = savedPipe.costPrice || 0;
                pipe.cutoffPrice = savedPipe.cutoffPrice || 0;
                pipe.quotedPrice = savedPipe.quotedPrice || pipe.cutoffPrice;
                pipe.hasCustomQuotedPrice = !!savedPipe.quotedPrice;
                pipe.gst = savedPipe.gst || 0;
                pipe.finalOfferPrice = savedPipe.finalOfferPrice || savedPipe.final_offer_price || 0;
                pipe.pricePerUom = savedPipe.price_per_uom || savedPipe.pricePerUom || 0;
                
                pipe.additionalMargin = savedPipe.additionalMargin || savedPipe.Additional_Margin__c || 0;
                pipe.tolerance = savedPipe.tolerance || savedPipe.Tolerance__c || 10;
                pipe.freight = savedPipe.freight || savedPipe.Freight__c || 0;
                pipe.freightCost = savedPipe.freightCost || savedPipe.freight_cost || 0;
                // Load customOD as a string to preserve values like "50,35" or "50x35"
                let rawCustomOD = savedPipe.custom_od || savedPipe.customOD;
                pipe.customOD = (rawCustomOD !== undefined && rawCustomOD !== null && rawCustomOD !== 0) ? String(rawCustomOD) : '';

                let rawCustomThk = savedPipe.custom_thickness || savedPipe.customThickness;
                pipe.customThickness = (rawCustomThk !== undefined && rawCustomThk !== null && rawCustomThk !== '') ? parseFloat(rawCustomThk) || 0 : 0;
                
                const savedReflect = savedPipe.reflect_in_offer_doc || savedPipe.reflectInOfferDoc || savedPipe.Reflect_In_Offer_Doc__c || 'Yes';
                pipe.reflectInOfferDocToggle = savedReflect === 'Yes';

                this.calculatePipe(pipe);
                pipe.totalPrice = savedPipe.total_price || savedPipe.totalPrice || 0;

                return pipe;
            });
        } else {
            this.pipes = [];
            for (let i = 0; i < this.pipeCount; i++) {
                let newPipe = this.createEmptyPipe(i);
                this.calculatePipe(newPipe);
                this.pipes.push(newPipe);
            }
        }
    }

    createEmptyPipe(index) {
        let std = 'IS 1239';
        
        // Dynamically get the first valid options so rows don't start broken
        let shapeOpts = this.getShapeOptions(std);
        let initShape = shapeOpts.length > 0 ? shapeOpts[0].value : '';
        
        let sizeOpts = this.getSizeOptions(std, initShape);
        let initSize = sizeOpts.length > 0 ? sizeOpts[0].value : '';
        
        let classOpts = this.getClassOptions(std, initShape, initSize);
        let initClass = classOpts.length > 0 ? classOpts[0].value : '';

        let isClassDisabled = false;
        let isClassDefault = false;
        
        if (classOpts.length === 1) {
            isClassDisabled = true;
            if (classOpts[0].value === 'Default') {
                isClassDisabled = false; // Opens up text input
                isClassDefault = true;
                initClass = ''; 
            }
        }

        return {
            id: index,
            key: `pipe_${index}_${Date.now()}`,
            steelType: 'Black Steel',
            designation: 'MS ERW',
            standardSpecGrade: std,
            shapeType: initShape,
            isShapeDisabled: shapeOpts.length === 1,
            pipeClass: initClass,
            isClassDisabled: isClassDisabled,
            isClassDefault: isClassDefault,
            sizeNb: initSize,
            endFinish: 'Plain End',
            pipeLength: '',
            specialDescription: '',
            customOD: 0,
            customThickness: 0,
            quantity: 1,
            uom: 'Pieces',
            discount: 0,
            additionalMargin: 0,
            tolerance: 10,
            freight: 0,
            freightCost: 0,
            reflectInOfferDocToggle: true,
            
            steelTypeOptions: STEEL_TYPE_OPTIONS,
            designationOptions: this.getDesignationOptions('Black Steel'),
            standardOptions: STANDARD_OPTIONS,
            shapeOptions: shapeOpts,
            classOptions: classOpts,
            sizeOptions: sizeOpts,
            endFinishOptions: END_FINISH_OPTIONS,
            uomOptions: UOM_OPTIONS,
            
            weightPerMeter: 0,
            singlePipeWeight: 0,
            totalWeight: 0,
            rateRsMtr: 0,
            costPrice: 0,
            cutoffPrice: 0,
            quotedPrice: 0,
            hasCustomQuotedPrice: false,
            gst: 0,
            finalOfferPrice: 0,
            pricePerUom: 0,
            totalPrice: 0,
            mappedOD: '',
            mappedNB: '',
            odOptions: [],
            isNbDriven: false,
            isOdDriven: false,
            isShapeDriven: false,
            isCustomDriven: false,
            isNbFirst: false
        };
    }

    getStdKey(standard) {
        if (!standard) return standard;
        if (standard === 'ASTM A 53 Grade B') return 'ASTMA-B';
        if (standard.startsWith('ASTM A 53') || standard.startsWith('ASTMA')) return 'ASTMA';
        if (standard === 'IS 4270') return 'IS 4270';
        return standard;
    }

    getDesignationOptions(steelType) {
        if (steelType === 'Black Steel') {
            return [
                { label: "MS ERW", value: "MS ERW" },
                { label: "CS ERW", value: "CS ERW" }
            ];
        } else if (steelType === 'Galvanized Iron (GI)') {
            return [
                { label: "GI ERW", value: "GI ERW" }
            ];
        }
        return DESIGNATION_OPTIONS;
    }

    getShapeOptions(standard) {
        let std = this.getStdKey(standard);
        if (std === 'ASTMA' || std === 'ASTMA-B') {
            return [
                { label: 'SCH-10', value: 'SCH-10' },
                { label: 'SCH-20', value: 'SCH-20' },
                { label: 'SCH-30', value: 'SCH-30' },
                { label: 'SCH-40', value: 'SCH-40' },
                { label: 'SCH-60', value: 'SCH-60' }
            ];
        }
        if (this.SHAPE_DEPENDENT_MAP && this.SHAPE_DEPENDENT_MAP[std]) {
            return this.SHAPE_DEPENDENT_MAP[std].map(opt => ({ label: opt, value: opt }));
        }
        return [{ label: 'Default', value: 'Default' }];
    }

    getODFromNB(standard, shape, nbValue) {
        let std = this.getStdKey(standard);
        if (!nbValue) return '';
        
        let num = nbValue.replace('mm', '').trim();
        
        if (std === 'IS 1239') {
            const is1239Map = {
                "Light": { "15": "21.4", "20": "26.9", "25": "33.8", "32": "42.5", "40": "48.5", "50": "60.2", "65": "76", "80": "88.7", "100": "113.9" },
                "Medium": { "15": "21.8", "20": "27.3", "25": "34.2", "32": "42.9", "40": "48.8", "50": "60.8", "65": "76.6", "80": "89.5", "100": "115", "125": "140.8", "150": "166.5" },
                "Heavy": { "15": "21.8", "20": "27.3", "25": "34.2", "32": "42.9", "40": "48.8", "50": "60.8", "65": "76.6", "80": "89.5", "100": "115", "125": "140.8", "150": "166.5" }
            };
            if (is1239Map[shape] && is1239Map[shape][num]) {
                return is1239Map[shape][num];
            }
        }
        
        if (STANDARD_DIMENSIONS_MAP[std] && STANDARD_DIMENSIONS_MAP[std][num]) {
            return STANDARD_DIMENSIONS_MAP[std][num];
        }
        return '';
    }

    getSizeOptions(standard, shape) {
        let std = this.getStdKey(standard);
        
        let lookupShape = shape;
        if (std === 'ASTMA' || std === 'ASTMA-B') {
            lookupShape = 'Default';
        }
        
        const keyPrefix1 = `${std}|${lookupShape}|`;
        const keyPrefix2 = `${standard}|${lookupShape}|`;
        const sizes = new Set();
        
        if(this.WEIGHT_MAP) {
            Object.keys(this.WEIGHT_MAP).forEach(k => {
                if (k.startsWith(keyPrefix1) || k.startsWith(keyPrefix2)) {
                    sizes.add(k.split('|')[3]);
                }
            });
        }
        
        let isNbDriven = ['IS 1239', 'IS 3589', 'IS 1161', 'IS 10577', 'ASTMA', 'ASTMA-B'].includes(std);

        let options = Array.from(sizes)
            // Sort options numerically so they appear in correct order
            .sort((a, b) => parseFloat(a.replace('mm', '')) - parseFloat(b.replace('mm', '')))
            .map(opt => {
                let label = opt.replace('mm', '');
                if (isNbDriven) {
                    let mappedOD = this.getODFromNB(standard, lookupShape, opt);
                    if (mappedOD) {
                        label = mappedOD;
                    }
                } else {
                    label = this.getDisplaySizeNb(std, lookupShape, label);
                }
                return { label: label, value: opt, mappedOD: label };
            });

        // ASTMA Schedule Filtering
        if (std === 'ASTMA' || std === 'ASTMA-B') {
            const astmaScheduleMap = {
                'SCH-10': ['200.0', '250.0', '300.0', '355.6', '406.4'],
                'SCH-20': ['219.1', '273.0', '323.9', '355.6', '406.4'],
                'SCH-30': ['219.1', '273.0', '323.9', '355.6', '406.4'],
                'SCH-40': ['21.3', '26.7', '33.4', '42.2', '48.3', '60.3', '73.0', '88.9', '101.6', '114.3', '141.3', '168.3', '200.0', '219.1', '250.0', '273.0', '300.0', '323.9', '355.6'],
                'SCH-60': ['219.1']
            };
            const validODs = astmaScheduleMap[shape];
            if (validODs) {
                options = options.filter(o => validODs.includes(o.mappedOD));
            }
        }
        
        return options;
    }

    getDisplaySizeNb(std, shape, label, customOD) {
        if (std === 'IS 4923') {
            if (customOD) {
                let customOdStr = String(customOD).trim();
                let parts = customOdStr.replace(/[xX,*_\/-]/g, ' ').split(/\s+/).filter(Boolean);
                if (parts.length >= 2) {
                    return `${parts[0]} x ${parts[1]}`;
                } else if (parts.length === 1) {
                    if (shape === 'Square') {
                        return `${parts[0]} x ${parts[0]}`;
                    } else {
                        return `${parts[0]}`;
                    }
                }
            }

            if (!label) return label;
            
            if (shape === 'Square') {
                return `${label} x ${label}`;
            } else if (shape === 'Rectangular') {
                const rectWidthMap = {
                    "50": 25, "60": 40, "66": 33, "70": 30, 
                    "75": 25, "80": 40, "96": 48, "100": 50, 
                    "122": 61, "145": 82, "150": 100, "172": 92,
                    "200": 100, "240": 120
                };
                if (rectWidthMap[label]) {
                    return `${label} x ${rectWidthMap[label]}`;
                }
            }
        }
        return label;
    }

    getClassOptions(standard, shape, sizeNb) {
        let std = this.getStdKey(standard);
        
        let lookupShape = shape;
        if (std === 'ASTMA' || std === 'ASTMA-B') {
            lookupShape = 'Default';
        }
        
        // 1. If we have a size, show only valid Classes for that size
        if (sizeNb && this.WEIGHT_MAP) {
            const keyPrefix1 = `${std}|${lookupShape}|`;
            const keyPrefix2 = `${standard}|${lookupShape}|`;
            const classes = new Set();
            Object.keys(this.WEIGHT_MAP).forEach(k => {
                if ((k.startsWith(keyPrefix1) || k.startsWith(keyPrefix2)) && k.endsWith(`|${sizeNb}`)) {
                    classes.add(k.split('|')[2]);
                }
            });
            if (classes.size > 0) {
                return Array.from(classes)
                    .sort((a, b) => parseFloat(a) - parseFloat(b))
                    .map(opt => ({ label: opt, value: opt }));
            }
        }

        // 2. If no size selected yet, provide all available classes for the shape
        const key = `${std}|${lookupShape}`;
        if (this.CLASS_DEPENDENT_MAP && this.CLASS_DEPENDENT_MAP[key] && this.CLASS_DEPENDENT_MAP[key].length > 0) {
            return this.CLASS_DEPENDENT_MAP[key].map(opt => ({ label: opt, value: opt }));
        }
        
        // 3. Absolute fallback
        return [{ label: 'Default', value: 'Default' }];
    }

            handleApply() {
        if (this.isReadOnly) { return; } 
        for (let i = 0; i < this.pipes.length; i++) {
            const p = this.pipes[i];
            // Skip WT/Class validation if user has entered a Custom Thickness
            if (p.classOptions && p.classOptions.length > 0 && !p.pipeClass && !p.isClassDefault && !(p.customThickness > 0)) {
                alert(`Row ${i + 1}: Please select a Wall Thickness / Class.`);
                return;
            }
        }

        const configuredPipes = this.pipes.map(pipe => {
            // Fallback logic: if standard field is empty, use custom value instead
            const effectivePipeClass = pipe.pipeClass || (pipe.customThickness > 0 ? String(pipe.customThickness) : '');
            const effectiveSizeNb = this.getDisplaySizeNb(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb, pipe.customOD) 
                                    || pipe.customOD 
                                    || '';
            const effectiveMappedOd = pipe.mappedOD || pipe.customOD || '';

            return {
                steel_type: pipe.steelType,
                pipe_designation: pipe.designation,
                standard: pipe.standardSpecGrade,
                shape: pipe.shapeType,
                pipe_class: effectivePipeClass,
                size_nb: effectiveSizeNb,
                raw_size_nb: pipe.sizeNb || pipe.customOD || '',
                mapped_od: effectiveMappedOd,
                mapped_nb: pipe.mappedNB || '',
                end_finish: pipe.endFinish,
                pipe_length: pipe.pipeLength ? pipe.pipeLength : 'NA',
                special_description_header: pipe.pipeLength ? String(pipe.pipeLength) : 'NA',
                special_description: pipe.specialDescription || '',
                custom_od: pipe.customOD || '',
                custom_thickness: pipe.customThickness || 0,
                quantity: pipe.quantity,
                uom: pipe.uom,
                discount: pipe.discount,
                singlePipeWeight: pipe.singlePipeWeight,
                totalWeight: pipe.totalWeight,
                rateRsMtr: pipe.rateRsMtr,
                costPrice: pipe.costPrice,
                cutoffPrice: pipe.cutoffPrice,
                quotedPrice: pipe.quotedPrice,
                gst: pipe.gst,
                finalOfferPrice: pipe.finalOfferPrice,
                pricePerUom: pipe.pricePerUom,
                totalPrice: pipe.totalPrice,
                freight: pipe.freight,
                freightCost: pipe.freightCost,
                reflectInOfferDocToggle: pipe.reflectInOfferDocToggle,
                reflectInOfferDoc: pipe.reflectInOfferDocToggle ? 'Yes' : 'No'
            };
        });

        this.dispatchEvent(new CustomEvent('saveconfig', {
            detail: {
                pipes: configuredPipes,
                showRateInDoc: this.showRateInDoc
            }
        }));
    }

    handleShowRateToggle(event) {
        this.showRateInDoc = event.target.checked;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('closemodal'));
    }

    handlePipeCountChange(event) {
        if (this.isReadOnly) { return; }
        let val = parseInt(event.target.value, 10);
        if (isNaN(val) || val < 1) val = 1;
        this.pipeCount = val;
        
        if (this.pipes.length < this.pipeCount) {
            for (let i = this.pipes.length; i < this.pipeCount; i++) {
                let newPipe = this.createEmptyPipe(i);
                this.calculatePipe(newPipe);
                this.pipes.push(newPipe);
            }
        } else if (this.pipes.length > this.pipeCount) {
            this.pipes = this.pipes.slice(0, this.pipeCount);
        }
    }

    toggleCalculations() {
        this.showCalculations = !this.showCalculations;
    }

    handleAddRow() {
        if (this.isReadOnly) { return; }
        this.pipeCount = this.pipes.length + 1;
        let newPipe = this.createEmptyPipe(this.pipes.length);
        this.calculatePipe(newPipe);
        this.pipes.push(newPipe);
        this.pipes = [...this.pipes];
    }

    handleDeleteRow(event) {
        if (this.isReadOnly) { return; }
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(index) && index >= 0 && index < this.pipes.length) {
            if (this.pipes.length === 1) {
                let newPipe = this.createEmptyPipe(0);
                this.calculatePipe(newPipe);
                this.pipes = [newPipe];
            } else {
                this.pipes.splice(index, 1);
                this.pipes = this.pipes.map((pipe, idx) => {
                    pipe.id = idx;
                    pipe.key = `pipe_${idx}_${Date.now()}`;
                    return pipe;
                });
                this.pipeCount = this.pipes.length;
            }
        }
    }

        handleFieldChange(event) {
        if (this.isReadOnly) { return; } 
        const fieldName = event.target.dataset.field;
        const index = parseInt(event.target.dataset.index, 10);
        const value = (event.target.type === 'toggle' || event.target.type === 'checkbox') ? event.target.checked : event.target.value;

        let pipe = this.pipes[index];
        pipe[fieldName] = value;

        // Dependency logic
        if (fieldName === 'steelType') {
            pipe.designationOptions = this.getDesignationOptions(value);
            if (!pipe.designationOptions.find(opt => opt.value === pipe.designation)) {
                pipe.designation = pipe.designationOptions.length > 0 ? pipe.designationOptions[0].value : '';
            }
        } else if (fieldName === 'standardSpecGrade') {
            pipe.shapeType = '';
            pipe.sizeNb = '';
            pipe.pipeClass = '';
            pipe.shapeOptions = this.getShapeOptions(pipe.standardSpecGrade);
            pipe.sizeOptions = [];
            pipe.classOptions = [];
            
            if (pipe.shapeOptions.length === 1) {
                pipe.shapeType = pipe.shapeOptions[0].value;
                pipe.isShapeDisabled = true;
                pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, pipe.shapeType);
                pipe.classOptions = this.getClassOptions(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
                
                if (pipe.classOptions.length === 1) {
                    if (pipe.classOptions[0].value === 'Default') {
                        pipe.pipeClass = '';
                        pipe.isClassDisabled = false;
                        pipe.isClassDefault = true;
                    } else {
                        pipe.pipeClass = pipe.classOptions[0].value;
                        pipe.isClassDisabled = true;
                        pipe.isClassDefault = false;
                    }
                } else {
                    pipe.isClassDisabled = false;
                    pipe.isClassDefault = false;
                }
            } else {
                pipe.isShapeDisabled = false;
                pipe.isClassDisabled = false;
            }
        } else if (fieldName === 'shapeType') {
            pipe.sizeNb = '';
            pipe.pipeClass = '';
            pipe.sizeOptions = this.getSizeOptions(pipe.standardSpecGrade, pipe.shapeType);
            pipe.classOptions = this.getClassOptions(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
            
            if (pipe.classOptions.length === 1) {
                if (pipe.classOptions[0].value === 'Default') {
                    pipe.pipeClass = '';
                    pipe.isClassDisabled = false;
                    pipe.isClassDefault = true;
                } else {
                    pipe.pipeClass = pipe.classOptions[0].value;
                    pipe.isClassDisabled = true;
                    pipe.isClassDefault = false;
                }
            } else {
                pipe.isClassDisabled = false;
                pipe.isClassDefault = false;
            }
        } else if (fieldName === 'sizeNb') {
            if (!pipe.isCustomDriven) {
                pipe.pipeClass = '';
                pipe.classOptions = this.getClassOptions(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
                
                if (pipe.classOptions.length === 1) {
                    if (pipe.classOptions[0].value === 'Default') {
                        pipe.pipeClass = '';
                        pipe.isClassDisabled = false;
                        pipe.isClassDefault = true;
                    } else {
                        pipe.pipeClass = pipe.classOptions[0].value;
                        pipe.isClassDisabled = true;
                        pipe.isClassDefault = false;
                    }
                } else {
                    pipe.isClassDisabled = false;
                    pipe.isClassDefault = false;
                }
            }
        }
        
        if (['pipeLength', 'quantity', 'discount', 'additionalMargin', 'customThickness', 'freight', 'tolerance'].includes(fieldName)) {
            pipe[fieldName] = parseFloat(value) || 0;
            // Any rate-affecting change should unlock the quoted price so it follows the new cutoff price
            pipe.hasCustomQuotedPrice = false;

            if (fieldName === 'customThickness') {
                if (pipe.customThickness > 0 || (pipe.customOD && String(pipe.customOD).trim().length > 0)) {
                    pipe.tolerance = 2;
                    pipe.additionalMargin = pipe.tolerance - 10;
                } else {
                    pipe.tolerance = 10;
                    pipe.additionalMargin = 0;
                }
            }
        }
        if (fieldName === 'customOD') {
            // Keep as raw string so "50,35" or "50x35" is preserved for two-sided shapes
            pipe.customOD = value || '';
            pipe.hasCustomQuotedPrice = false;
        }
        if (fieldName === 'quotedPrice') {
            if (value === null || value === undefined || value === '') {
                // The field is blank because the user is mid-edit (e.g. cleared it
                // to type a replacement number). Don't revert to cutoff price yet -
                // calculatePipe() runs below on every keystroke, and if
                // hasCustomQuotedPrice were false here it would immediately snap
                // the value back to cutoffPrice, making it impossible to ever type
                // a new number. We keep hasCustomQuotedPrice=true so calculatePipe
                // leaves quotedPrice alone while blank. The actual cutoff fallback
                // is applied on blur - see handleQuotedPriceBlur - only if the
                // field is still empty once the user leaves it.
                pipe.quotedPrice = null;
                pipe.hasCustomQuotedPrice = true;
            } else {
                pipe.hasCustomQuotedPrice = true;
                pipe.quotedPrice = parseFloat(value) || 0;
            }
        }

        // ── TOLERANCE LOGIC FOR CUSTOM FIELDS ──
        // If EITHER customThickness OR customOD is provided, tolerance becomes 2.
        // Only when BOTH are cleared does tolerance reset to 10.
        if (fieldName === 'customThickness' || fieldName === 'customOD') {
            const hasCustomThickness = pipe.customThickness > 0;
            const hasCustomOD = pipe.customOD && String(pipe.customOD).trim() !== '';
            if (hasCustomThickness || hasCustomOD) {
                pipe.tolerance = 2;
                pipe.additionalMargin = pipe.tolerance - 10; // -8
            } else {
                pipe.tolerance = 10;
                pipe.additionalMargin = 0;
            }
        }

        if (fieldName === 'additionalMargin') {
            pipe.tolerance = 10 + pipe.additionalMargin;
        } else if (fieldName === 'tolerance') {
            pipe.additionalMargin = pipe.tolerance - 10;
        }

        this.calculatePipe(pipe);
        this.pipes = [...this.pipes];
    }

    // Fires on blur of the quotedPrice input. If the user genuinely leaves the
    // field empty, THIS is where it falls back to cutoff price - not on every
    // keystroke while they're still typing (see handleFieldChange above).
    // Requires the quotedPrice input in the template to have
    // onblur={handleQuotedPriceBlur} alongside its existing data-index attribute.
    handleQuotedPriceBlur(event) {
        if (this.isReadOnly) { return; }
        const index = parseInt(event.target.dataset.index, 10);
        const pipe = this.pipes[index];
        if (!pipe) { return; }

        if (pipe.quotedPrice === null || pipe.quotedPrice === undefined || pipe.quotedPrice === '') {
            pipe.hasCustomQuotedPrice = false;
        }
        this.calculatePipe(pipe);
        this.pipes = [...this.pipes];
    }

    calculatePipe(pipe) {
        let std = this.getStdKey(pipe.standardSpecGrade);
        
        pipe.isNbDriven = ['IS 1239', 'IS 3589', 'IS 1161', 'IS 10577', 'ASTMA', 'ASTMA-B'].includes(std);
        pipe.isOdDriven = (std === 'IS 9295');
        pipe.isShapeDriven = (std === 'IS 4923');
        pipe.isCustomDriven = (std === 'IS 3601');
        pipe.isNbFirst = (std === 'IS 4270');

        if (pipe.isNbDriven) {
            pipe.mappedOD = this.getODFromNB(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
            pipe.mappedNB = pipe.sizeNb ? pipe.sizeNb.replace('mm', '') : '';
        } else if (pipe.isNbFirst) {
            pipe.mappedOD = this.getODFromNB(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb) || '';
            pipe.mappedNB = pipe.sizeNb ? pipe.sizeNb.replace('mm', '') : '';
            pipe.odOptions = pipe.mappedOD ? [{ label: pipe.mappedOD, value: pipe.mappedOD }] : [];
        } else if (pipe.isOdDriven) {
            pipe.mappedOD = '';
            pipe.mappedNB = '';
        } else if (pipe.isShapeDriven) {
            pipe.mappedOD = '';
            pipe.mappedNB = '';
        }

        let mappedWeight = null;
        if (!pipe.customOD && !pipe.customThickness) {
            let lookupShape = pipe.shapeType;
            if (std === 'ASTMA' || std === 'ASTMA-B') {
                lookupShape = 'Default';
            }
            let key1 = `${std}|${lookupShape}|${pipe.pipeClass}|${pipe.sizeNb}`;
            let key2 = `${pipe.standardSpecGrade}|${lookupShape}|${pipe.pipeClass}|${pipe.sizeNb}`;
            
            if (this.WEIGHT_MAP) {
                if (this.WEIGHT_MAP[key1]) mappedWeight = this.WEIGHT_MAP[key1];
                else if (this.WEIGHT_MAP[key2]) mappedWeight = this.WEIGHT_MAP[key2];
            }
        }

        if (mappedWeight) {
            pipe.weightPerMeter = Number(mappedWeight);
        } else {
            let trueODStr = this.getODFromNB(pipe.standardSpecGrade, pipe.shapeType, pipe.sizeNb);
            let trueOD = parseFloat(trueODStr);
            let customODFirst = pipe.customOD ? parseFloat(String(pipe.customOD).replace(/[xX,*_\/-]/g, ' ').trim().split(/\s+/)[0]) || 0 : 0;
            let odVal = customODFirst > 0 ? customODFirst : (trueOD || parseFloat(pipe.sizeNb.replace('mm', '')) || 0);
            let thkVal = pipe.customThickness > 0 ? pipe.customThickness : (parseFloat(pipe.pipeClass) || 0);
            
            if (pipe.isCustomDriven) {
                // For IS 3601, weight formula is: (OD - Thickness) * Thickness * 0.0246615
                let od = parseFloat(pipe.sizeNb) || parseFloat(pipe.customOD) || 0;
                let thk = parseFloat(pipe.pipeClass) || parseFloat(pipe.customThickness) || 0;
                if (od > 0 && thk > 0) {
                    pipe.weightPerMeter = (od - thk) * thk * 0.0246615;
                } else {
                    pipe.weightPerMeter = 0;
                }
            } else if (pipe.isShapeDriven) { 
                let side1 = odVal;
                let side2 = side1;
                
                if (pipe.customOD) {
                    let customOdStr = String(pipe.customOD).trim();
                    let parts = customOdStr.replace(/[xX,*_\/-]/g, ' ').split(/\s+/).filter(Boolean);
                    if (parts.length >= 2) {
                        side1 = parseFloat(parts[0]) || side1;
                        side2 = parseFloat(parts[1]) || side2;
                    } else if (parts.length === 1) {
                        side1 = parseFloat(parts[0]) || side1;
                        side2 = side1; // treat as square if only one side entered
                    }
                } else if (pipe.shapeType === 'Rectangular') {
                    const rectWidthMap = {
                        "50": 25, "60": 40, "66": 33, "70": 30, 
                        "75": 25, "80": 40, "96": 48, "100": 50, 
                        "122": 61, "145": 82, "172": 92
                    };
                    side2 = rectWidthMap[String(side1)] || side1;
                }
                pipe.weightPerMeter = Number((((side1 + side2) - (4.145 * thkVal)) * 0.0160344 * thkVal).toFixed(3));
            } else {
                pipe.weightPerMeter = Number(((odVal - thkVal) * thkVal * 0.0246615).toFixed(3));
            }
        }
        
        pipe.singlePipeWeight = pipe.weightPerMeter;

        let pipeLength = parseFloat(pipe.pipeLength) || 1;
        let qty = parseFloat(pipe.quantity) || 0;

        if (pipe.uom === 'MT') {
            pipe.totalWeight = qty * 1000;
        } else if (pipe.uom === 'Meters') {
            pipe.totalWeight = qty * pipe.weightPerMeter;
        } else {
            pipe.totalWeight = qty * pipe.weightPerMeter * pipeLength;
        }

        let baseRateKg = this.dynamicBaseRates[pipe.steelType] || 0;

        let desc = pipe.specialDescription ? pipe.specialDescription.toUpperCase() : '';
        let isMSorCS = (pipe.designation === 'MS ERW' || pipe.designation === 'CS ERW');
        let isGI = (pipe.designation === 'GI ERW');

        if (pipe.endFinish === 'Beveled End' || pipe.endFinish === 'Bevelled End') {
            baseRateKg += 0.50;
        } else if (pipe.endFinish === 'Just Threaded' || pipe.endFinish === 'Threaded') {
            baseRateKg += 0.75;
        } else if (pipe.endFinish === 'Threaded and Socketed') {
            baseRateKg += 1.50;
        }

        if (isMSorCS) {
            if (desc.includes('VARNISH')) {
                baseRateKg += 0.50;
            }
            let pipeLen = parseFloat(pipe.pipeLength);
            if (!isNaN(pipeLen) && pipeLen < 4.50) {
                baseRateKg += 0.50;
            }
            if (desc.includes('GR - III') || desc.includes('GR-III') || desc.includes('FE-410') || desc.includes('FE 410') || desc.includes('YST 240') || desc.includes('YST-240')) {
                baseRateKg += 0.60;
            }
            if (desc.includes('GR - V') || desc.includes('GR-V') || desc.includes('YST 310') || desc.includes('YST-310')) {
                baseRateKg += 2.00;
            }
        }

        if (isGI) {
            if (desc.includes('80 MICRON') || desc.includes('500-600 GSM') || desc.includes('500 - 600 GSM')) {
                baseRateKg += 8.00;
            }
            if (desc.includes('100 MICRON')) {
                baseRateKg += 20.00;
            }
            if (desc.includes('SWS')) {
                baseRateKg += 0.75;
            }
            if (desc.includes('S/S') || desc.includes('S / S')) {
                baseRateKg += 1.50;
            }
        }

        let freightVal = parseFloat(pipe.freight) || 0;
        let fCost = 0;
        if (pipe.uom === 'MT') {
            fCost = freightVal * 1000;
        } else if (pipe.uom === 'Meters') {
            fCost = freightVal * pipe.weightPerMeter;
        } else {
            let lengthVal = parseFloat(pipe.pipeLength) || 1;
            fCost = freightVal * pipe.weightPerMeter * lengthVal;
        }
        pipe.freightCost = Number(fCost.toFixed(2));
        
        pipe.rateRsMtr = Number(baseRateKg.toFixed(2));
        
        let A = pipe.weightPerMeter;
        let B = pipe.rateRsMtr;
        if (pipe.uom === 'MT') {
            pipe.pricePerUom = Number((B * 1000).toFixed(2));
        } else if (pipe.uom === 'Meters') {
            pipe.pricePerUom = Number((A * B).toFixed(2));
        } else {
            let lengthVal = parseFloat(pipe.pipeLength) || 1;
            pipe.pricePerUom = Number((A * B * lengthVal).toFixed(2));
        }
        
        pipe.costPrice = Number((pipe.pricePerUom + pipe.freightCost).toFixed(2));

        let tol = parseFloat(pipe.tolerance) || 0;
        pipe.cutoffPrice = Number((pipe.costPrice - (pipe.costPrice * (tol / 100))).toFixed(2));
        
        if (!pipe.hasCustomQuotedPrice) {
            pipe.quotedPrice = pipe.cutoffPrice;
        }
        
        let gstRate = (this.dynamicGst !== undefined && this.dynamicGst !== null) ? this.dynamicGst : 18;
        pipe.gst = Number((pipe.quotedPrice * (gstRate / 100)).toFixed(2));
        pipe.finalOfferPrice = Number((pipe.quotedPrice + pipe.gst).toFixed(2));
        
        if (pipe.costPrice > 0) {
            pipe.discount = Number((((pipe.costPrice - pipe.quotedPrice) / pipe.costPrice) * 100).toFixed(2));
        } else {
            pipe.discount = 0;
        }
        
        pipe.totalPrice = Number((pipe.finalOfferPrice * qty).toFixed(2));
        pipe.toleranceDisplay = pipe.tolerance ? -pipe.tolerance : 0;
    }

    @api
    getConfigurationData() {
        return this.pipes.map(p => ({
            Steel_Type__c: p.steelType,
            Designation__c: p.designation,
            Standard__c: p.standardSpecGrade,
            Shape__c: p.shapeType,
            Pipe_Class__c: p.pipeClass,
            Size__c: p.sizeNb,
            End_Finish__c: p.endFinish,
            Length__c: p.pipeLength,
            Quantity__c: p.quantity,
            UOM__c: p.uom,
            Discount__c: p.discount,
            Additional_Margin__c: p.additionalMargin,
            Tolerance__c: p.tolerance,
            Cutoff_Price__c: p.cutoffPrice,
            Freight__c: p.freight,
            Reflect_In_Offer_Doc__c: p.reflectInOfferDocToggle ? 'Yes' : 'No',
            Total_Weight__c: p.totalWeight,
            Total_Price__c: p.totalPrice
        }));
    }
}