import { defineMermaidSetup } from '@slidev/types'

export default defineMermaidSetup(() => {
  return {
    theme: 'base',
    themeVariables: {
      primaryColor: '#EE0000',
      primaryTextColor: '#151515',
      primaryBorderColor: '#C7C7C7',
      secondaryColor: '#F2F2F2',
      secondaryTextColor: '#4D4D4D',
      tertiaryColor: '#E0E0E0',
      lineColor: '#C7C7C7',
      textColor: '#151515',
      mainBkg: '#FFFFFF',
      nodeBorder: '#C7C7C7',
      clusterBkg: '#F2F2F2',
      titleColor: '#151515',
      edgeLabelBackground: '#FFFFFF',
      fontFamily: '"Red Hat Text", Helvetica, Arial, sans-serif',
    },
  }
})
