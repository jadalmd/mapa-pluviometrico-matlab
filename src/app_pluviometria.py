import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
import matplotlib.pyplot as plt
from scipy.interpolate import griddata
import pymannkendall as mk
import calendar

# --- CONFIGURAÇÃO DA INTERFACE ---
st.set_page_config(page_title="UNIPLU-BR: Sistema de Análise Pluviométrica", layout="wide")

def local_css(file_name):
    st.markdown(f'<style>{open(file_name).read()}</style>', unsafe_allow_html=True)

st.title("🌧️ UNIPLU-BR: Ferramenta Integrada de Análise Pluviométrica")
st.markdown("---")

# --- CARREGAMENTO DE DADOS (CACHE) ---
@st.cache_data
def load_data():
    paths = ["data/processed/df_monthly_filtered_with_geo.csv", "df_monthly_filtered_with_geo.csv"]
    df = None
    for p in paths:
        try:
            df = pd.read_csv(p)
            break
        except FileNotFoundError:
            continue
    
    if df is None:
        st.error("Arquivo de dados não encontrado. Certifique-se de que o CSV de saída do pré-processamento existe.")
        st.stop()
        
    df['datetime'] = pd.to_datetime(df[['year', 'month']].assign(DAY=1))
    return df

df_full = load_data()

# --- SIDEBAR: CONTROLE GLOBAL ---
st.sidebar.header("🕹️ Painel de Controle")
modulo = st.sidebar.radio("Selecione o Módulo:", ["Análise Macro (Estado/Mapas)", "Análise Micro (Painel da Estação)"])

st.sidebar.divider()
estados_disp = sorted(df_full['state'].dropna().unique())
estado_sel = st.sidebar.selectbox("Estado:", estados_disp)
df_estado = df_full[df_full['state'] == estado_sel].copy()

# ==============================================================================
# MÓDULO 1: ANÁLISE MACRO (Baseado no mapapluviometria.m)
# ==============================================================================
if modulo == "Análise Macro (Estado/Mapas)":
    st.header(f"📍 Análise Regional: {estado_sel}")
    
    tab1, tab2, tab3 = st.tabs(["🗺️ Distribuição Espacial", "📈 Séries Temporais Estaduais", "🏘️ Comparação Municipal"])

    with tab1:
        st.subheader("Mapas de Precipitação Anual (Contourf)")
        ano_mapa = st.selectbox("Selecione o Ano:", sorted(df_estado['year'].unique(), reverse=True))
        
        # Agregação anual por estação para o mapa
        df_mapa = df_estado[df_estado['year'] == ano_mapa].groupby(['gauge_code', 'lat', 'long', 'city'])['rain_mm'].sum().reset_index()
        
        if len(df_mapa) > 3:
            # Lógica de Interpolação (Griddata)
            x, y, z = df_mapa['long'].values, df_mapa['lat'].values, df_mapa['rain_mm'].values
            xi = np.linspace(x.min(), x.max(), 100)
            yi = np.linspace(y.min(), y.max(), 100)
            xi, yi = np.meshgrid(xi, yi)
            zi = griddata((x, y), z, (xi, yi), method='cubic')

            fig_map, ax = plt.subplots(figsize=(10, 7))
            cnt = ax.contourf(xi, yi, zi, levels=20, cmap="YlGnBu")
            ax.scatter(x, y, c='black', s=5, alpha=0.3)
            plt.colorbar(cnt, label="Chuva Total (mm)")
            ax.set_title(f"Distribuição Espacial - {ano_mapa}")
            st.pyplot(fig_map)
            
            # Relatório Tangível
            max_r = df_mapa.loc[df_mapa['rain_mm'].idxmax()]
            min_r = df_mapa.loc[df_mapa['rain_mm'].idxmin()]
            st.write(f"**Destaques de {ano_mapa}:**")
            st.info(f"🏆 Mais Chuvoso: {max_r['city']} ({max_r['rain_mm']:.1f} mm) | 🏜️ Mais Seco: {min_r['city']} ({min_r['rain_mm']:.1f} mm)")
        else:
            st.warning("Dados insuficientes para gerar o mapa deste ano.")

    with tab2:
        st.subheader("Estatísticas Estaduais Agregadas")
        df_agg = df_estado.groupby('year')['rain_mm'].mean().reset_index()
        ltm = df_agg['rain_mm'].mean()
        
        # Gráfico de Anomalias (Cores condicionais)
        df_agg['Anomalia'] = df_agg['rain_mm'] - ltm
        df_agg['cor'] = ['#3399cc' if x >= 0 else '#cc4c4c' for x in df_agg['Anomalia']]
        
        fig_anom = go.Figure(go.Bar(x=df_agg['year'], y=df_agg['Anomalia'], marker_color=df_agg['cor']))
        fig_anom.update_layout(title="Anomalias de Precipitação (Desvios da Média Histórica)")
        st.plotly_chart(fig_anom, use_container_width=True)
        
        # Média Móvel (Passa-Baixa)
        df_agg['MA5'] = df_agg['rain_mm'].rolling(window=5, center=True).mean()
        fig_ma = px.line(df_agg, x='year', y=['rain_mm', 'MA5'], title="Filtro Passa-Baixa (5 Anos)")
        st.plotly_chart(fig_ma, use_container_width=True)

    with tab3:
        st.subheader("Comparativo entre Municípios")
        muns = st.multiselect("Selecione os Municípios:", sorted(df_estado['city'].unique()))
        if muns:
            df_comp = df_estado[df_estado['city'].isin(muns)].groupby(['year', 'city'])['rain_mm'].sum().reset_index()
            fig_comp = px.line(df_comp, x='year', y='rain_mm', color='city', markers=True)
            st.plotly_chart(fig_comp, use_container_width=True)

# ==============================================================================
# MÓDULO 2: PAINEL DA ESTAÇÃO (Baseado no uniplu_station_panel.m)
# ==============================================================================
else:
    st.header(f"📊 Painel Detalhado da Estação")
    
    df_estado['label'] = df_estado['city'] + " | " + df_estado['gauge_code']
    estacao_sel = st.selectbox("Selecione a Estação:", sorted(df_estado['label'].unique()))
    
    cod_est = estacao_sel.split(" | ")[1]
    df_st = df_estado[df_estado['gauge_code'] == cod_est].sort_values('datetime')

    # 1. Matriz de Disponibilidade
    st.subheader("Data Availability Matrix")
    df_st['status'] = df_st['rain_mm'].notna().astype(int)
    pivot = df_st.pivot(index='month', columns='year', values='status').reindex(range(1,13))
    
    fig_heat = go.Figure(data=go.Heatmap(
        z=pivot.values, x=pivot.columns, y=[calendar.month_abbr[i] for i in range(1,13)],
        colorscale=[[0, '#d95454'], [1, '#45a359']], showscale=False
    ))
    fig_heat.update_layout(height=350, yaxis=dict(autorange="reversed"))
    st.plotly_chart(fig_heat, use_container_width=True)

    # 2. Hietograma Mensal
    st.subheader("Monthly Hyetograph")
    fig_hyeto = px.bar(df_st, x='datetime', y='rain_mm', color_discrete_sequence=['#3373cc'])
    st.plotly_chart(fig_hyeto, use_container_width=True)

    # 3. Totais Anuais (REGRA ESTRITA: 12 meses)
    st.subheader("Annual Totals & Trend (Strict 12-Month Rule)")
    df_ann = df_st.groupby('year').agg({'rain_mm': ['sum', 'count']}).reset_index()
    df_ann.columns = ['year', 'rain_sum', 'month_count']
    
    # Aplicação da regra rigorosa do MATLAB
    df_ann['rain_strict'] = np.where(df_ann['month_count'] == 12, df_ann['rain_sum'], np.nan)
    df_valid = df_ann.dropna(subset=['rain_strict'])

    # Cálculo MK
    res_mk = mk.original_test(df_valid['rain_strict'].values) if len(df_valid) > 3 else None
    trend_txt = f"MK p={res_mk.p:.4f} | Sen={res_mk.slope:.2f} | {res_mk.trend}" if res_mk else "Dados insuficientes para MK"
    
    fig_ann = go.Figure()
    fig_ann.add_trace(go.Scatter(x=df_ann['year'], y=df_ann['rain_strict'], mode='lines+markers', name="Total Anual"))
    fig_ann.update_layout(title=f"Série Anual: {trend_txt}")
    st.plotly_chart(fig_ann, use_container_width=True)